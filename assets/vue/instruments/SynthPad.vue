<script setup lang="ts">
// Synth pad — eight chords, three flavors (Warm / Bell / Sweep).
// Same chord set as the guitar (C / Am / Dm / G / E / Em / F / B7),
// routed through long-envelope synths so the chord swells in and
// fades out as ambience under whatever else is playing.
//
//   - Warm: triangle PolySynth, gentle analog-pad swell
//   - Bell: FMSynth, glassy bell-tone with harmonic shimmer
//   - Sweep: sawtooth + filter envelope, classic 80s-pad sweep

import { onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll, type ChordName } from "@/lib/audio"
import { FLASH_MS, REMOTE_FLASH_DELTA_MS } from "@/lib/motion"

const props = defineProps<{
  remoteHit: { instrument: string; note: string; t: number } | null
}>()

const live = useLiveVue()

type PadStyle = "warm" | "bell" | "sweep"
type StyleOption = { id: PadStyle; label: string }

const styles: StyleOption[] = [
  { id: "warm", label: "Warm" },
  { id: "bell", label: "Bell" },
  { id: "sweep", label: "Sweep" },
]

const style = ref<PadStyle>("warm")

// Octave offset relative to the engine's default chord voicing.
const octaveOffset = ref(0)
const OCTAVE_MIN = -2
const OCTAVE_MAX = 2

function shiftOctave(delta: number) {
  const next = octaveOffset.value + delta
  if (next < OCTAVE_MIN || next > OCTAVE_MAX) return
  stopAll("pad", style.value)
  octaveOffset.value = next
}

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
const remoteFlashing = ref<ChordName | null>(null)
let flashTimer: number | null = null
let remoteFlashTimer: number | null = null

function flash(name: ChordName) {
  flashing.value = name
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  // Pads sustain longer than other instruments — let the visual
  // mirror that with a longer flash.
  flashTimer = window.setTimeout(() => (flashing.value = null), FLASH_MS.long)
}

const chordNames = new Set<string>(["C", "Am", "Dm", "G", "E", "Em", "F", "B7"])

function flashRemote(name: ChordName) {
  remoteFlashing.value = name
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  remoteFlashTimer = window.setTimeout(
    () => (remoteFlashing.value = null),
    FLASH_MS.long + REMOTE_FLASH_DELTA_MS,
  )
}

watch(
  () => props.remoteHit,
  (hit) => {
    if (!hit || hit.instrument !== "pad") return
    if (chordNames.has(hit.note)) flashRemote(hit.note as ChordName)
  },
)

async function trigger(name: ChordName) {
  await ensureStarted()
  play("pad", style.value, name, octaveOffset.value)
  flash(name)
  live.pushEvent("note", {
    instrument: "pad",
    style: style.value,
    chord: name,
    octave_offset: octaveOffset.value,
  })
}

function selectStyle(id: PadStyle) {
  if (id === style.value) return
  stopAll("pad", style.value)
  style.value = id
}

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  const c = chords.find((x) => x.key === event.key)
  if (c) {
    event.preventDefault()
    trigger(c.name)
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
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  // Cut any pad still ringing when leaving the instrument.
  stopAll("pad", style.value)
})
</script>

<template>
  <div class="space-y-4">
    <div class="flex flex-wrap items-center gap-3">
      <!-- Style selector -->
      <div class="flex items-center gap-1">
        <span class="text-xs uppercase tracking-wider text-muted-foreground mr-2">Style</span>
        <button
          v-for="s in styles"
          :key="s.id"
          @click="selectStyle(s.id)"
          :class="[
            'px-3 py-1 text-xs rounded-md border transition-colors',
            style === s.id
              ? 'bg-accent-pad text-background border-accent-pad'
              : 'bg-card hover:bg-accent text-muted-foreground border-input'
          ]"
        >
          {{ s.label }}
        </button>
      </div>

      <!-- Octave offset -->
      <div class="flex items-center gap-1 ml-auto">
        <span class="text-xs uppercase tracking-wider text-muted-foreground mr-2">Oct</span>
        <button
          @click="shiftOctave(-1)"
          :disabled="octaveOffset <= OCTAVE_MIN"
          class="px-2 py-1 text-xs rounded-md border bg-card hover:bg-accent text-muted-foreground border-input disabled:opacity-30 disabled:cursor-not-allowed"
        >
          −
        </button>
        <span class="text-sm tabular-nums font-mono w-8 text-center">
          {{ octaveOffset > 0 ? `+${octaveOffset}` : octaveOffset }}
        </span>
        <button
          @click="shiftOctave(1)"
          :disabled="octaveOffset >= OCTAVE_MAX"
          class="px-2 py-1 text-xs rounded-md border bg-card hover:bg-accent text-muted-foreground border-input disabled:opacity-30 disabled:cursor-not-allowed"
        >
          +
        </button>
      </div>
    </div>

    <!-- Chord buttons -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
      <button
        v-for="c in chords"
        :key="c.name"
        @pointerdown.prevent="trigger(c.name)"
        :class="[
          'rounded-md border bg-card flex flex-col items-center justify-center gap-2 py-6 select-none transition-all active:scale-95 hover:bg-accent',
          flashing === c.name && 'ring-2 ring-accent-pad scale-95 glow-pad',
          remoteFlashing === c.name && flashing !== c.name && 'ring-2 ring-orange-400'
        ]"
      >
        <div class="text-2xl font-bold">{{ c.name }}</div>
        <kbd class="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground font-mono">{{ c.key }}</kbd>
      </button>
    </div>
  </div>
</template>
