<script setup lang="ts">
// Drum pad — the first instrument. Five pads (kick / snare / hi-hat /
// open hat / crash). Tap the buttons or press 1–5 on the keyboard.
//
// Local audio plays immediately on tap (zero latency for the player).
// The note is also pushed to the LiveView, which broadcasts it via
// Phoenix.PubSub to every other connected user; their LV pushes
// "play_remote_note" back down to *this* component, which then plays
// the same drum locally for them.
//
// Self-events are filtered server-side (StudioLive checks user_id),
// so `play_remote_note` only ever fires for *other* users' hits.

import { onMounted, onUnmounted, ref } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, playDrum, type DrumName } from "@/lib/audio"

const live = useLiveVue()

type Pad = { name: DrumName; label: string; key: string }

const pads: Pad[] = [
  { name: "kick", label: "Kick", key: "1" },
  { name: "snare", label: "Snare", key: "2" },
  { name: "hihat", label: "Hi-hat", key: "3" },
  { name: "open_hat", label: "Open Hat", key: "4" },
  { name: "crash", label: "Crash", key: "5" },
]

// Brief flash on the pad that just played, for visual feedback.
const flashing = ref<DrumName | null>(null)
let flashTimer: number | null = null

function flash(name: DrumName) {
  flashing.value = name
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashing.value = null), 120)
}

async function hit(name: DrumName) {
  await ensureStarted()
  playDrum(name)
  flash(name)
  live.pushEvent("note", { instrument: "drums", note: name })
}

// Receive remote players' drum hits from the LiveView.
live.handleEvent("play_remote_note", async (payload: { instrument: string; note: DrumName }) => {
  if (payload.instrument !== "drums") return
  await ensureStarted()
  playDrum(payload.note)
  flash(payload.note)
})

// Keyboard shortcuts: 1–5.
function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  const pad = pads.find((p) => p.key === event.key)
  if (pad) {
    event.preventDefault()
    hit(pad.name)
  }
}

onMounted(() => window.addEventListener("keydown", onKey))
onUnmounted(() => {
  window.removeEventListener("keydown", onKey)
  if (flashTimer !== null) window.clearTimeout(flashTimer)
})
</script>

<template>
  <div class="grid grid-cols-2 sm:grid-cols-5 gap-3">
    <button
      v-for="p in pads"
      :key="p.name"
      @pointerdown.prevent="hit(p.name)"
      :class="[
        'aspect-square rounded-md border bg-card flex flex-col items-center justify-center gap-2 select-none transition-all active:scale-95 hover:bg-accent',
        flashing === p.name && 'ring-2 ring-primary scale-95'
      ]"
    >
      <div class="text-base font-medium">{{ p.label }}</div>
      <kbd class="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{{ p.key }}</kbd>
    </button>
  </div>
</template>
