<script setup lang="ts">
// The single Vue island for the studio. Owns:
//   - cross-instrument audio receiver (remote players' notes)
//   - the active instrument pad (rendered via v-if from a prop)
//
// Why one island instead of three?
// live_vue 1.2's destroyed() hook *defers* `app.unmount()` until the
// next `phx:page-loading-stop` event — see hooks.ts:78. That event
// only fires on full-page navigation, not on WebSocket-driven LV
// re-renders. So if we have <.DrumPad /> swapping to <.GuitarPad />
// at the HEEX level, each swap leaves the previous Vue app alive
// forever, with its keydown listeners still attached to window.
// After a few switches every keystroke fires multiple instruments
// at once.
//
// Wrapping the pads in a single Vue island fixes it: v-if is pure
// Vue, so the inner pad's onUnmounted properly fires on switch and
// AbortController + stopAllX run as designed.

import { onMounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import DrumPad from "@/instruments/DrumPad.vue"
import KeyboardPad from "@/instruments/KeyboardPad.vue"
import GuitarPad from "@/instruments/GuitarPad.vue"
import {
  ensureStarted,
  play,
  setMasterVolume,
  type DrumName,
  type ChordName,
} from "@/lib/audio"

defineProps<{
  current_instrument: "drums" | "keyboard" | "guitar"
}>()

const live = useLiveVue()

type RemoteNote =
  | { instrument: "drums"; style: string; note: DrumName }
  | { instrument: "keyboard"; style: string; note: string }
  | { instrument: "guitar"; style: string; chord: ChordName }

// Latest remote hit, broadcast down to whichever pad is currently
// mounted so it can flash the matching button. New object on every
// hit (timestamped) so Vue's watcher always re-fires, even if two
// rapid hits target the same note.
type RemoteHit = { instrument: string; note: string; t: number }
const lastRemoteHit = ref<RemoteHit | null>(null)

// Master output volume slider. Persisted per-user in localStorage —
// each browser remembers where you set it last.
//
// localStorage and Tone.js are browser-only; live_vue runs this
// `<script setup>` on the server too via SSR. Defer to onMounted
// (client-only) for the initial read + Tone.Destination call.
const VOLUME_KEY = "mixwave:volume"
const volume = ref(80)

watch(volume, (v) => {
  // The watch only fires from user interaction with the slider —
  // never during SSR — so localStorage and Tone are safe here.
  setMasterVolume(v / 100)
  localStorage.setItem(VOLUME_KEY, String(v))
})

onMounted(() => {
  const stored = Number.parseInt(localStorage.getItem(VOLUME_KEY) ?? "80", 10)
  if (Number.isFinite(stored)) {
    volume.value = Math.max(0, Math.min(100, stored))
  }
  setMasterVolume(volume.value / 100)
})

// Replay-last-30s. Vue requests a burst from LV; LV pushes back the
// note buffer with offsets; we schedule each via setTimeout from
// "now". Local-only — others don't hear our replay.
type ReplayEvent = {
  instrument: string
  style: string
  note?: string
  chord?: string
  offset_ms: number
}

const isReplaying = ref(false)
let replayTimers: number[] = []

function startReplay() {
  if (isReplaying.value) return
  isReplaying.value = true
  live.pushEvent("request_replay", {})
}

function stopReplay() {
  for (const id of replayTimers) window.clearTimeout(id)
  replayTimers = []
  isReplaying.value = false
}

live.handleEvent("replay_burst", ({ events }: { events: ReplayEvent[] }) => {
  // Cancel any in-flight replay before scheduling the new one.
  for (const id of replayTimers) window.clearTimeout(id)
  replayTimers = []

  if (!events || events.length === 0) {
    isReplaying.value = false
    return
  }

  for (const e of events) {
    const id = window.setTimeout(async () => {
      await ensureStarted()
      const note = e.instrument === "guitar" ? e.chord : e.note
      if (note) play(e.instrument, e.style ?? "synth", note)
    }, e.offset_ms)
    replayTimers.push(id)
  }

  // Mark replay finished a bit after the last scheduled event.
  const tail = events[events.length - 1].offset_ms
  const doneId = window.setTimeout(() => {
    isReplaying.value = false
  }, tail + 200)
  replayTimers.push(doneId)
})

// Cross-instrument audio: every user hears every other user with the
// sender's chosen style, no matter which pad *they* have on screen.
live.handleEvent("play_remote_note", async (payload: RemoteNote) => {
  await ensureStarted()
  // Drums + keyboard carry `note`; guitar carries `chord`. Normalize
  // to a single string for the engine + the remote-flash signal.
  const note = payload.instrument === "guitar" ? payload.chord : payload.note
  play(payload.instrument, payload.style ?? "synth", note)
  lastRemoteHit.value = { instrument: payload.instrument, note, t: Date.now() }
})
</script>

<template>
  <div class="space-y-4">
    <!-- Top controls: replay last 30s + master volume -->
    <div class="flex items-center justify-end gap-3">
      <button
        @click="isReplaying ? stopReplay() : startReplay()"
        :class="[
          'px-3 py-1 text-xs rounded-md border transition-colors',
          isReplaying
            ? 'bg-destructive/10 text-destructive border-destructive/40'
            : 'bg-card hover:bg-accent text-muted-foreground border-input'
        ]"
      >
        {{ isReplaying ? "Stop replay" : "Replay 30s" }}
      </button>

      <span class="text-xs uppercase tracking-wider text-muted-foreground">Vol</span>
      <input
        v-model.number="volume"
        type="range"
        min="0"
        max="100"
        class="w-32 accent-primary"
      />
      <span class="text-xs tabular-nums text-muted-foreground w-10 text-right">
        {{ volume }}%
      </span>
    </div>

    <DrumPad v-if="current_instrument === 'drums'" :remote-hit="lastRemoteHit" />
    <KeyboardPad
      v-else-if="current_instrument === 'keyboard'"
      :remote-hit="lastRemoteHit"
    />
    <GuitarPad
      v-else-if="current_instrument === 'guitar'"
      :remote-hit="lastRemoteHit"
    />
  </div>
</template>
