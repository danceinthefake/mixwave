<script setup lang="ts">
// Guitar pad — eight common chord buttons, each rendered as a
// chord-fingering diagram (X/O indicators above the strings, then
// a mini fretboard with finger dots). Click a chord or press 1–8.
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

// Octave offset relative to the engine's default chord voicing.
// 0 = stock; +1 = whole chord up an octave; -1 = down.
const octaveOffset = ref(0)
const OCTAVE_MIN = -2
const OCTAVE_MAX = 2

function shiftOctave(delta: number) {
  const next = octaveOffset.value + delta
  if (next < OCTAVE_MIN || next > OCTAVE_MAX) return
  stopAll("guitar", style.value)
  octaveOffset.value = next
}

// Chord fingerings in standard guitar tab notation: 6-element array
// from low E (left) to high E (right). "x" = muted string, 0 = open
// string, n = press at fret n. `barre` overlays a bar across all
// strings at that fret (only F here, but easy to extend).
//
// 12 chords laid out 4 × 3 — the most common open-position chords
// a beginner guitarist learns: 6 majors, 3 minors, 3 dominant 7ths.
type FretPos = number | "x"
type Fingering = { positions: FretPos[]; barre?: number }
type Chord = { name: ChordName; key: string; fingering: Fingering }

const chords: Chord[] = [
  // Row 1 — popular open majors
  { name: "C", key: "1", fingering: { positions: ["x", 3, 2, 0, 1, 0] } },
  { name: "G", key: "2", fingering: { positions: [3, 2, 0, 0, 0, 3] } },
  { name: "D", key: "3", fingering: { positions: ["x", "x", 0, 2, 3, 2] } },
  { name: "A", key: "4", fingering: { positions: ["x", 0, 2, 2, 2, 0] } },
  // Row 2 — minors + F barre
  { name: "Am", key: "5", fingering: { positions: ["x", 0, 2, 2, 1, 0] } },
  { name: "Em", key: "6", fingering: { positions: [0, 2, 2, 0, 0, 0] } },
  { name: "Dm", key: "7", fingering: { positions: ["x", "x", 0, 2, 3, 1] } },
  { name: "F", key: "8", fingering: { positions: [1, 3, 3, 2, 1, 1], barre: 1 } },
  // Row 3 — extras + dominant 7ths
  { name: "E", key: "9", fingering: { positions: [0, 2, 2, 1, 0, 0] } },
  { name: "B7", key: "0", fingering: { positions: ["x", 2, 1, 2, 0, 2] } },
  { name: "A7", key: "-", fingering: { positions: ["x", 0, 2, 0, 2, 0] } },
  { name: "D7", key: "=", fingering: { positions: ["x", "x", 0, 2, 1, 2] } },
]

const FRET_ROWS = 4

const flashing = ref<ChordName | null>(null)
const remoteFlashing = ref<ChordName | null>(null)
let flashTimer: number | null = null
let remoteFlashTimer: number | null = null

function flash(name: ChordName) {
  flashing.value = name
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashing.value = null), 250)
}

const chordNames = new Set<string>(chords.map((c) => c.name))

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
  play("guitar", style.value, name, octaveOffset.value)
  flash(name)
  live.pushEvent("note", {
    instrument: "guitar",
    style: style.value,
    chord: name,
    octave_offset: octaveOffset.value,
  })
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
  // Cut any chord still ringing when leaving the instrument.
  stopAll("guitar", style.value)
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
              ? 'bg-accent-guitar text-background border-accent-guitar'
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
        <span class="text-sm tabular-nums w-8 text-center">
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

    <!-- Chord buttons. Each button shows the actual fingering as a
         mini chord diagram: X / O above each string, then a 6×4
         fretboard with dots at fret positions. -->
    <div class="grid grid-cols-2 sm:grid-cols-4 gap-3">
      <button
        v-for="c in chords"
        :key="c.name"
        @pointerdown.prevent="strum(c.name)"
        :class="[
          'rounded-md border bg-card flex flex-col items-center gap-2 py-4 px-3 select-none transition-all active:scale-95 hover:bg-accent',
          flashing === c.name && 'ring-2 ring-accent-guitar scale-95',
          remoteFlashing === c.name && flashing !== c.name && 'ring-2 ring-orange-400'
        ]"
      >
        <div class="text-xl font-bold">{{ c.name }}</div>

        <!-- Chord diagram. Width fixed so 6 strings stay legible. -->
        <div class="w-[5.5rem]">
          <!-- Top labels (X for muted, O for open, blank when fretted) -->
          <div class="grid grid-cols-6 text-[10px] text-center text-muted-foreground mb-0.5">
            <span v-for="(p, i) in c.fingering.positions" :key="i">
              {{ p === 'x' ? 'X' : p === 0 ? 'O' : '' }}
            </span>
          </div>

          <!-- Fretboard. Column-major flow so each string fills a
               vertical column of 4 fret cells. -->
          <div class="relative border border-amber-700/60 bg-amber-950/40 rounded-sm overflow-hidden">
            <div
              class="grid grid-cols-6 grid-rows-4 gap-px bg-amber-800/40"
              style="grid-auto-flow: column;"
            >
              <template v-for="(p, sIdx) in c.fingering.positions" :key="sIdx">
                <div
                  v-for="fret in FRET_ROWS"
                  :key="`${sIdx}-${fret}`"
                  class="relative bg-amber-950/70"
                  style="aspect-ratio: 1;"
                >
                  <span
                    v-if="p === fret"
                    class="absolute inset-1 rounded-full bg-accent-guitar/90"
                  />
                </div>
              </template>
            </div>
            <!-- Barre overlay across all strings at the barre fret -->
            <div
              v-if="c.fingering.barre"
              class="absolute left-1 right-1 h-1 bg-accent-guitar/80 rounded-full -translate-y-1/2 pointer-events-none"
              :style="{ top: `${((c.fingering.barre - 0.5) / FRET_ROWS) * 100}%` }"
            />
          </div>
        </div>

        <kbd class="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{{ c.key }}</kbd>
      </button>
    </div>
  </div>
</template>
