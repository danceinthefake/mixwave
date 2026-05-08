<script setup lang="ts">
// Drum pad — five pads (kick / snare / hi-hat / open hat / crash).
// Tap the buttons or press 1–5 on the keyboard.
//
// Local audio plays immediately on tap (zero latency); the note is
// pushed to the LiveView for broadcast. Remote players' notes are
// handled by JamReceiver — see assets/vue/JamReceiver.vue — which
// is always mounted regardless of the active instrument.

import { onMounted, onUnmounted, ref } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll, type DrumName } from "@/lib/audio"

// The Style selector UI lands in a follow-up commit; pads default
// to "synth" for now.
const style = "synth"

const live = useLiveVue()

type Pad = { name: DrumName; label: string; key: string }

const pads: Pad[] = [
  { name: "kick", label: "Kick", key: "1" },
  { name: "snare", label: "Snare", key: "2" },
  { name: "hihat", label: "Hi-hat", key: "3" },
  { name: "open_hat", label: "Open Hat", key: "4" },
  { name: "crash", label: "Crash", key: "5" },
]

const flashing = ref<DrumName | null>(null)
let flashTimer: number | null = null

function flash(name: DrumName) {
  flashing.value = name
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashing.value = null), 120)
}

async function hit(name: DrumName) {
  await ensureStarted()
  play("drums", style, name)
  flash(name)
  live.pushEvent("note", { instrument: "drums", style, note: name })
}

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  const pad = pads.find((p) => p.key === event.key)
  if (pad) {
    event.preventDefault()
    hit(pad.name)
  }
}

// AbortController guarantees the listener is torn down even if Vue's
// onUnmounted somehow runs out of order with the component's setup.
// One .abort() removes everything attached with this signal.
let controller: AbortController | null = null

onMounted(() => {
  controller = new AbortController()
  window.addEventListener("keydown", onKey, { signal: controller.signal })
})

onUnmounted(() => {
  controller?.abort()
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  stopAll("drums", style)
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
