<script setup lang="ts">
// The single Vue island for the chamber. Owns:
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
import * as Tone from "tone"
import DrumPad from "@/instruments/DrumPad.vue"
import KeyboardPad from "@/instruments/KeyboardPad.vue"
import GuitarPad from "@/instruments/GuitarPad.vue"
import BassPad from "@/instruments/BassPad.vue"
import SynthPad from "@/instruments/SynthPad.vue"
import {
  ensureStarted,
  play,
  setMasterVolume,
  setChamberKind,
  type ChamberKind,
  type DrumName,
  type ChordName,
} from "@/lib/audio"

const props = defineProps<{
  current_instrument: "drums" | "keyboard" | "guitar" | "bass" | "pad"
  chamber_kind: ChamberKind
}>()

// Apply the chamber's audio character on mount + whenever the
// LiveView updates the prop (creator changing the kind, or a
// remote :chamber_updated broadcast). The setter is idempotent;
// calling it with the same value is a cheap no-op.
watch(
  () => props.chamber_kind,
  (kind) => {
    if (kind) setChamberKind(kind)
  },
  { immediate: true },
)

const live = useLiveVue()

type StrumPhase = "press" | "release"
type RemoteNote =
  | { instrument: "drums"; style: string; note: DrumName }
  | { instrument: "keyboard"; style: string; note: string }
  | {
      instrument: "guitar"
      style: string
      chord: ChordName
      octave_offset?: number
      phase?: StrumPhase
      up_strum?: boolean
    }
  | { instrument: "bass"; style: string; note: string }
  | { instrument: "pad"; style: string; chord: ChordName; octave_offset?: number }

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
  // If the AudioContext is already running (e.g., the user
  // navigated here from another page where they interacted),
  // skip the gate.
  if (Tone.context?.state === "running") {
    audioReady.value = true
  }
})

// Tap-to-enter overlay: browsers won't let AudioContext start until
// the user makes a gesture on the page. Without this gate, an
// incoming remote note that arrives before the local user has tapped
// anything tries to start the context from inside an event handler
// that the browser doesn't count as a gesture, gets blocked, and
// silently fails. The overlay forces a real click before any audio
// can be played.
const audioReady = ref(false)

async function enterChamber() {
  await ensureStarted()
  audioReady.value = true
}

// Replay-last-30s. Vue requests a burst from LV; LV pushes back the
// note buffer with offsets; we schedule each via setTimeout from
// "now". Local-only — others don't hear our replay.
type ReplayEvent = {
  instrument: string
  style: string
  note?: string
  chord?: string
  octave_offset?: number
  phase?: StrumPhase
  up_strum?: boolean
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
      // guitar + pad carry chord; everything else carries note.
      const note = e.chord ?? e.note
      if (!note) return
      const opts = e.phase
        ? { phase: e.phase, upStrum: e.up_strum }
        : undefined
      play(e.instrument, e.style ?? "synth", note, e.octave_offset ?? 0, opts)
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
  // Drums + keyboard + bass carry `note`; guitar + pad carry `chord`.
  // Normalize to a single string for the engine + the remote-flash
  // signal. octave_offset applies to chord-based instruments;
  // phase ("press" / "release") applies to guitar only.
  const note = "chord" in payload ? payload.chord : payload.note
  const octaveOffset = "octave_offset" in payload ? payload.octave_offset ?? 0 : 0
  const phase = "phase" in payload ? payload.phase : undefined
  const upStrum = "up_strum" in payload ? payload.up_strum : undefined
  const opts = phase ? { phase, upStrum } : undefined
  play(payload.instrument, payload.style ?? "synth", note, octaveOffset, opts)
  // Only flash on press, not on release — release events would
  // double-flash the pad otherwise.
  if (phase !== "release") {
    lastRemoteHit.value = { instrument: payload.instrument, note, t: Date.now() }
  }
})
</script>

<template>
  <!-- Tap-to-enter overlay. Covers everything until the user makes
       a real gesture on the page so the browser will let
       AudioContext start. Without this, the first remote-note event
       (which arrives in a non-gesture context) can't play and we
       lose audio for whatever happened before the local user
       tapped anything themselves. -->
  <Transition
    enter-active-class="transition-opacity duration-200"
    leave-active-class="transition-opacity duration-300"
    enter-from-class="opacity-0"
    leave-to-class="opacity-0"
  >
    <div
      v-if="!audioReady"
      @click="enterChamber"
      class="fixed inset-0 z-50 flex items-center justify-center backdrop-blur-md bg-background/80 cursor-pointer select-none"
    >
      <div class="flex flex-col items-center gap-6 text-center px-4">
        <img
          src="/images/logo.svg"
          alt=""
          class="size-20 motion-safe:animate-pulse"
        />
        <div class="space-y-1">
          <h2 class="text-2xl font-bold tracking-tight font-display">
            Tap to start jamming
          </h2>
          <p class="text-sm text-muted-foreground">
            Browsers need a gesture before audio can play
          </p>
        </div>
        <button
          class="rounded-lg border bg-card hover:bg-accent px-6 py-2.5 text-sm font-medium transition-colors"
        >
          Enter chamber
        </button>
      </div>
    </div>
  </Transition>

  <div class="space-y-4">
    <!-- Top control strip: replay + master volume. Floating-bar
         look matches the bottom dock for visual consistency. -->
    <div class="flex justify-end">
      <div class="flex items-center gap-3 rounded-xl border bg-card/60 backdrop-blur-sm px-3 py-1.5 shadow-sm">
        <button
          @click="isReplaying ? stopReplay() : startReplay()"
          :class="[
            'px-2.5 py-1 text-xs rounded-md transition-colors cursor-pointer',
            isReplaying
              ? 'bg-destructive/10 text-destructive'
              : 'text-muted-foreground hover:bg-accent hover:text-foreground'
          ]"
        >
          {{ isReplaying ? "Stop replay" : "↩ Replay 30s" }}
        </button>

        <div class="w-px h-5 bg-border"></div>

        <span class="text-xs uppercase tracking-wider text-muted-foreground">Vol</span>
        <input
          v-model.number="volume"
          type="range"
          min="0"
          max="100"
          class="w-28 accent-primary"
        />
        <span class="text-xs tabular-nums font-mono text-muted-foreground w-9 text-right">
          {{ volume }}%
        </span>
      </div>
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
    <BassPad v-else-if="current_instrument === 'bass'" :remote-hit="lastRemoteHit" />
    <SynthPad v-else-if="current_instrument === 'pad'" :remote-hit="lastRemoteHit" />
  </div>
</template>
