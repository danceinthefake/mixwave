<script setup lang="ts">
// Guitar pad — eight common chord buttons (C / Am / Dm / G / E / Em
// / F / B7). Click a button or press 1–8.
//
// Each chord is a stack of notes triggered on a Tone.PluckSynth
// (Karplus-Strong) wrapped in a PolySynth so the strings ring
// together. Local play + push; JamReceiver handles remote audio.

import { onMounted, onUnmounted, ref } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll, type ChordName } from "@/lib/audio"

const style = "synth"

const live = useLiveVue()

type Chord = { name: ChordName; key: string }

const chords: Chord[] = [
  { name: "C", key: "1" },
  { name: "Am", key: "2" },
  { name: "Dm", key: "3" },
  { name: "G", key: "4" },
  { name: "E", key: "5" },
  { name: "Em", key: "6" },
  { name: "F", key: "7" },
  { name: "B7", key: "8" },
]

const flashing = ref<ChordName | null>(null)
let flashTimer: number | null = null

function flash(name: ChordName) {
  flashing.value = name
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashing.value = null), 250)
}

async function strum(name: ChordName) {
  await ensureStarted()
  play("guitar", style, name)
  flash(name)
  live.pushEvent("note", { instrument: "guitar", style, chord: name })
}

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  const c = chords.find((x) => x.key === event.key)
  if (c) {
    event.preventDefault()
    strum(c.name)
  }
}

let controller: AbortController | null = null

onMounted(() => {
  controller = new AbortController()
  window.addEventListener("keydown", onKey, { signal: controller.signal })
})

onUnmounted(() => {
  controller?.abort()
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  // Cut any chord still ringing — BRAINSTORM §9: held notes cut off
  // on instrument switch.
  stopAll("guitar", style)
})
</script>

<template>
  <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
    <button
      v-for="c in chords"
      :key="c.name"
      @pointerdown.prevent="strum(c.name)"
      :class="[
        'rounded-md border bg-card flex flex-col items-center justify-center gap-2 py-6 select-none transition-all active:scale-95 hover:bg-accent',
        flashing === c.name && 'ring-2 ring-primary scale-95'
      ]"
    >
      <div class="text-2xl font-bold">{{ c.name }}</div>
      <kbd class="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{{ c.key }}</kbd>
    </button>
  </div>
</template>
