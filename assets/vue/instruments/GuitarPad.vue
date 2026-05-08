<script setup lang="ts">
// Guitar pad — eight common chord buttons + a Style selector with
// three flavors. Click a chord or press 1–8.
//
//   - Synth: PolySynth(MonoSynth) with sweeping filter envelope
//   - Pluck: hand-rolled Karplus-Strong (works in non-secure contexts)
//   - Acoustic: real guitar samples streamed from a CDN
//
// Local play + push; remote audio goes through JamReceiver.

import { onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll, preload, type ChordName } from "@/lib/audio"

const props = defineProps<{
  remoteHit: { instrument: string; note: string; t: number } | null
}>()

const live = useLiveVue()

type GuitarStyle = "synth" | "pluck" | "acoustic"
type StyleOption = { id: GuitarStyle; label: string }

const styles: StyleOption[] = [
  { id: "synth", label: "Synth" },
  { id: "pluck", label: "Pluck" },
  { id: "acoustic", label: "Acoustic" },
]

const style = ref<GuitarStyle>("synth")

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
  flashTimer = window.setTimeout(() => (flashing.value = null), 250)
}

const chordNames = new Set<string>(["C", "Am", "Dm", "G", "E", "Em", "F", "B7"])

function flashRemote(name: ChordName) {
  remoteFlashing.value = name
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  // Chords visibly ring longer than drums; mirror that with a longer flash.
  remoteFlashTimer = window.setTimeout(() => (remoteFlashing.value = null), 350)
}

watch(
  () => props.remoteHit,
  (hit) => {
    if (!hit || hit.instrument !== "guitar") return
    if (chordNames.has(hit.note)) flashRemote(hit.note as ChordName)
  },
)

async function strum(name: ChordName) {
  await ensureStarted()
  play("guitar", style.value, name)
  flash(name)
  live.pushEvent("note", { instrument: "guitar", style: style.value, chord: name })
}

function selectStyle(id: GuitarStyle) {
  if (id === style.value) return
  // Cut any chord still ringing on the previous flavor.
  stopAll("guitar", style.value)
  style.value = id
  // Acoustic flavor preloads its samples from the CDN here so the
  // first strum isn't silent while samples download.
  preload("guitar", id)
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
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  // Cut any chord still ringing — BRAINSTORM §9: held notes cut off
  // on instrument switch.
  stopAll("guitar", style.value)
})
</script>

<template>
  <div class="space-y-4">
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
            ? 'bg-primary text-primary-foreground border-primary'
            : 'bg-card hover:bg-accent text-muted-foreground border-input'
        ]"
      >
        {{ s.label }}
      </button>
    </div>

    <!-- Chord buttons -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
      <button
        v-for="c in chords"
        :key="c.name"
        @pointerdown.prevent="strum(c.name)"
        :class="[
          'rounded-md border bg-card flex flex-col items-center justify-center gap-2 py-6 select-none transition-all active:scale-95 hover:bg-accent',
          flashing === c.name && 'ring-2 ring-primary scale-95',
          remoteFlashing === c.name && flashing !== c.name && 'ring-2 ring-orange-400'
        ]"
      >
        <div class="text-2xl font-bold">{{ c.name }}</div>
        <kbd class="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{{ c.key }}</kbd>
      </button>
    </div>
  </div>
</template>
