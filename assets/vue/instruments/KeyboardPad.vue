<script setup lang="ts">
// Keyboard pad — one octave of piano keys (C4 → C5). Click white or
// black keys, or use the QWERTY row mapping:
//
//   a w s e d f t g y h u j k
//   C C# D D# E F F# G G# A A# B C5
//
// PolySynth lets multiple keys ring at once. JamReceiver handles
// remote players' notes — pads only push.

import { onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll, preload } from "@/lib/audio"

const props = defineProps<{
  remoteHit: { instrument: string; note: string; t: number } | null
}>()

const live = useLiveVue()

type KeyboardStyle = "synth" | "lead" | "piano"
type StyleOption = { id: KeyboardStyle; label: string }

const styles: StyleOption[] = [
  { id: "synth", label: "Synth" },
  { id: "lead", label: "Lead" },
  { id: "piano", label: "Piano" },
]

const style = ref<KeyboardStyle>("synth")

type WhiteKey = { note: string; key: string; label: string }
type BlackKey = { note: string; key: string; label: string; afterIdx: number }

// Indexed positions for the 8 white keys (C, D, E, F, G, A, B, C5).
const whiteKeys: WhiteKey[] = [
  { note: "C4", key: "a", label: "C" },
  { note: "D4", key: "s", label: "D" },
  { note: "E4", key: "d", label: "E" },
  { note: "F4", key: "f", label: "F" },
  { note: "G4", key: "g", label: "G" },
  { note: "A4", key: "h", label: "A" },
  { note: "B4", key: "j", label: "B" },
  { note: "C5", key: "k", label: "C" },
]

// Black keys sit *between* specific white keys. afterIdx is the
// index of the white key the black key sits immediately after.
const blackKeys: BlackKey[] = [
  { note: "C#4", key: "w", label: "C#", afterIdx: 0 },
  { note: "D#4", key: "e", label: "D#", afterIdx: 1 },
  { note: "F#4", key: "t", label: "F#", afterIdx: 3 },
  { note: "G#4", key: "y", label: "G#", afterIdx: 4 },
  { note: "A#4", key: "u", label: "A#", afterIdx: 5 },
]

const flashingNote = ref<string | null>(null)
const remoteFlashingNote = ref<string | null>(null)
let flashTimer: number | null = null
let remoteFlashTimer: number | null = null

function flash(note: string) {
  flashingNote.value = note
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashingNote.value = null), 180)
}

function flashRemote(note: string) {
  remoteFlashingNote.value = note
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  remoteFlashTimer = window.setTimeout(() => (remoteFlashingNote.value = null), 250)
}

watch(
  () => props.remoteHit,
  (hit) => {
    if (!hit || hit.instrument !== "keyboard") return
    flashRemote(hit.note)
  },
)

async function hit(note: string) {
  await ensureStarted()
  play("keyboard", style.value, note)
  flash(note)
  live.pushEvent("note", { instrument: "keyboard", style: style.value, note })
}

function selectStyle(id: KeyboardStyle) {
  if (id === style.value) return
  // Cut held notes on the previous flavor before switching.
  stopAll("keyboard", style.value)
  style.value = id
  // Sampled flavors (Piano) start their CDN download here so the
  // first key press isn't silent while samples load.
  preload("keyboard", id)
}

const allKeys = [
  ...whiteKeys.map((k) => ({ ...k, kind: "white" as const })),
  ...blackKeys.map((k) => ({ ...k, kind: "black" as const })),
]

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  const k = allKeys.find((x) => x.key === event.key)
  if (k) {
    event.preventDefault()
    hit(k.note)
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
  // BRAINSTORM §9: held notes cut off on instrument switch.
  stopAll("keyboard", style.value)
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

    <!-- Keyboard -->
    <div class="relative h-44 select-none mx-auto" style="max-width: 560px;">
      <!-- white keys -->
    <div class="absolute inset-0 flex">
      <button
        v-for="key in whiteKeys"
        :key="key.note"
        @pointerdown.prevent="hit(key.note)"
        :class="[
          'flex-1 border rounded-b-md flex flex-col items-center justify-end pb-3 transition-all',
          flashingNote === key.note
            ? 'bg-primary text-primary-foreground border-primary'
            : remoteFlashingNote === key.note
              ? 'bg-orange-100 text-orange-900 border-orange-400'
              : 'bg-white text-slate-700 border-border hover:bg-slate-100 active:bg-slate-200'
        ]"
      >
        <span class="text-sm font-medium">{{ key.label }}</span>
        <kbd class="mt-1 text-[10px] px-1 py-0.5 rounded bg-slate-200 text-slate-600">{{ key.key }}</kbd>
      </button>
    </div>
    <!-- black keys overlay -->
    <button
      v-for="bk in blackKeys"
      :key="bk.note"
      @pointerdown.prevent.stop="hit(bk.note)"
      :style="{ left: `calc(${(bk.afterIdx + 1) * (100 / whiteKeys.length)}% - 0.875rem)` }"
      :class="[
        'absolute top-0 w-7 h-28 rounded-b-md border border-black flex flex-col items-center justify-end pb-2 transition-all',
        flashingNote === bk.note
          ? 'bg-primary'
          : remoteFlashingNote === bk.note
            ? 'bg-orange-500'
            : 'bg-slate-900 text-slate-200 hover:bg-slate-800 active:bg-slate-700'
      ]"
    >
      <span class="text-[10px]">{{ bk.label }}</span>
      <kbd class="mt-1 text-[9px] px-1 rounded bg-slate-700 text-slate-300">{{ bk.key }}</kbd>
    </button>
    </div>
  </div>
</template>
