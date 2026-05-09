<script setup lang="ts">
// Bass pad — fretboard layout. 4 strings (E A D G, standard bass
// tuning) × 5 fret positions, chromatic per string. Click any
// position, or use the QWERTY shortcut grid:
//
//   G string (top of screen):    1 2 3 4 5
//   D string:                    q w e r t
//   A string:                    a s d f g
//   E string (bottom of screen): z x c v b
//
// Each row of QWERTY = one string; columns 1-5 = open + 4 frets.
// Top-of-screen string is on top-of-keyboard row, so the visual
// layout maps directly onto the keys you press.
//
//   Style flavors:
//     - Synth: punchy sawtooth MonoSynth with a sweeping filter
//     - Sub: pure sine sub-bass for deep low-end
//     - Slap: bandpass-filtered square for funky slap-bass feel
//
// Bass is monophonic; one note at a time. Local play + push;
// remote audio goes through Studio.vue's receiver.

import { computed, onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll } from "@/lib/audio"
import { FLASH_MS, REMOTE_FLASH_DELTA_MS } from "@/lib/motion"

const props = defineProps<{
  remoteHit: { instrument: string; note: string; t: number } | null
}>()

const live = useLiveVue()

type BassStyle = "synth" | "sub" | "slap"
type StyleOption = { id: BassStyle; label: string }

const styles: StyleOption[] = [
  { id: "synth", label: "Synth" },
  { id: "sub", label: "Sub" },
  { id: "slap", label: "Slap" },
]

const style = ref<BassStyle>("synth")

// Octave for the E string. Default 1 → standard tuning E1 A1 D2 G2.
const baseOctave = ref(1)
const OCTAVE_MIN = 0
const OCTAVE_MAX = 3
const FRET_COUNT = 5

type Fret = { note: string; label: string; key: string }
type GuitarString = { label: string; openNote: string; frets: Fret[] }

// Strings rendered top-to-bottom in tab convention: highest-pitched
// (G) on top, lowest (E) on the bottom. Each string holds 5
// chromatic frets (open + four).
//
// Note layout per string at standard tuning:
//   G2: G  G# A  A# B
//   D2: D  D# E  F  F#
//   A1: A  A# B  C  C#  ← note jump to next octave at fret 3
//   E1: E  F  F# G  G#
// Each row of QWERTY corresponds to one string, 5 keys per row.
// Order matches screen layout (G top → E bottom = number row top
// → z-row bottom).
const STRING_SHORTCUTS = {
  G: ["1", "2", "3", "4", "5"],
  D: ["q", "w", "e", "r", "t"],
  A: ["a", "s", "d", "f", "g"],
  E: ["z", "x", "c", "v", "b"],
}

const strings = computed<GuitarString[]>(() => {
  const lo = baseOctave.value
  const hi = baseOctave.value + 1
  const k = STRING_SHORTCUTS
  return [
    {
      label: "G",
      openNote: `G${hi}`,
      frets: [
        { note: `G${hi}`, label: "G", key: k.G[0] },
        { note: `G#${hi}`, label: "G#", key: k.G[1] },
        { note: `A${hi}`, label: "A", key: k.G[2] },
        { note: `A#${hi}`, label: "A#", key: k.G[3] },
        { note: `B${hi}`, label: "B", key: k.G[4] },
      ],
    },
    {
      label: "D",
      openNote: `D${hi}`,
      frets: [
        { note: `D${hi}`, label: "D", key: k.D[0] },
        { note: `D#${hi}`, label: "D#", key: k.D[1] },
        { note: `E${hi}`, label: "E", key: k.D[2] },
        { note: `F${hi}`, label: "F", key: k.D[3] },
        { note: `F#${hi}`, label: "F#", key: k.D[4] },
      ],
    },
    {
      label: "A",
      openNote: `A${lo}`,
      frets: [
        { note: `A${lo}`, label: "A", key: k.A[0] },
        { note: `A#${lo}`, label: "A#", key: k.A[1] },
        { note: `B${lo}`, label: "B", key: k.A[2] },
        { note: `C${hi}`, label: "C", key: k.A[3] },
        { note: `C#${hi}`, label: "C#", key: k.A[4] },
      ],
    },
    {
      label: "E",
      openNote: `E${lo}`,
      frets: [
        { note: `E${lo}`, label: "E", key: k.E[0] },
        { note: `F${lo}`, label: "F", key: k.E[1] },
        { note: `F#${lo}`, label: "F#", key: k.E[2] },
        { note: `G${lo}`, label: "G", key: k.E[3] },
        { note: `G#${lo}`, label: "G#", key: k.E[4] },
      ],
    },
  ]
})

function shiftOctave(delta: number) {
  const next = baseOctave.value + delta
  if (next < OCTAVE_MIN || next > OCTAVE_MAX) return
  stopAll("bass", style.value)
  baseOctave.value = next
}

const flashing = ref<string | null>(null)
const remoteFlashing = ref<string | null>(null)
let flashTimer: number | null = null
let remoteFlashTimer: number | null = null

function flash(note: string) {
  flashing.value = note
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashing.value = null), FLASH_MS.medium)
}

function flashRemote(note: string) {
  remoteFlashing.value = note
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  remoteFlashTimer = window.setTimeout(
    () => (remoteFlashing.value = null),
    FLASH_MS.medium + REMOTE_FLASH_DELTA_MS,
  )
}

watch(
  () => props.remoteHit,
  (hit) => {
    if (!hit || hit.instrument !== "bass") return
    flashRemote(hit.note)
  },
)

async function hit(note: string) {
  await ensureStarted()
  play("bass", style.value, note)
  flash(note)
  live.pushEvent("note", { instrument: "bass", style: style.value, note })
}

function selectStyle(id: BassStyle) {
  if (id === style.value) return
  stopAll("bass", style.value)
  style.value = id
}

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  for (const s of strings.value) {
    const f = s.frets.find((x) => x.key === event.key)
    if (f) {
      event.preventDefault()
      hit(f.note)
      return
    }
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
  stopAll("bass", style.value)
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
              ? 'bg-accent-bass text-background border-accent-bass'
              : 'bg-card hover:bg-accent text-muted-foreground border-input'
          ]"
        >
          {{ s.label }}
        </button>
      </div>

      <!-- Octave shift — moves all four strings together. -->
      <div class="flex items-center gap-1 ml-auto">
        <span class="text-xs uppercase tracking-wider text-muted-foreground mr-2">Oct</span>
        <button
          @click="shiftOctave(-1)"
          :disabled="baseOctave <= OCTAVE_MIN"
          class="px-2 py-1 text-xs rounded-md border bg-card hover:bg-accent text-muted-foreground border-input disabled:opacity-30 disabled:cursor-not-allowed"
        >
          −
        </button>
        <span class="text-sm tabular-nums font-mono w-6 text-center">{{ baseOctave }}</span>
        <button
          @click="shiftOctave(1)"
          :disabled="baseOctave >= OCTAVE_MAX"
          class="px-2 py-1 text-xs rounded-md border bg-card hover:bg-accent text-muted-foreground border-input disabled:opacity-30 disabled:cursor-not-allowed"
        >
          +
        </button>
      </div>
    </div>

    <!-- Fretboard. Wood-toned background and inlay dot at fret 3,
         the way real basses mark position. Open notes (column 0)
         get a darker treatment to read like the nut. -->
    <div class="overflow-x-auto -mx-2 px-2">
      <div class="mx-auto" style="min-width: 560px; max-width: 760px;">
        <!-- Fret-number header -->
        <div class="grid grid-cols-[2.5rem_repeat(5,1fr)] gap-1 mb-1">
          <div></div>
          <div
            v-for="n in FRET_COUNT"
            :key="n"
            class="text-center text-[10px] uppercase tracking-wider text-muted-foreground"
          >
            {{ n - 1 === 0 ? "Open" : n - 1 }}
          </div>
        </div>
        <div class="rounded-md overflow-hidden border bg-amber-950/20">
          <div
            v-for="s in strings"
            :key="s.label"
            class="grid grid-cols-[2.5rem_repeat(5,1fr)] gap-px bg-amber-900/40"
          >
            <div class="flex items-center justify-center text-xs font-bold text-amber-200/90 bg-amber-950/60">
              {{ s.label }}
            </div>
            <button
              v-for="(f, fi) in s.frets"
              :key="f.note"
              @pointerdown.prevent="hit(f.note)"
              :class="[
                'relative h-12 flex flex-col items-center justify-center select-none transition-all active:scale-95',
                fi === 0 ? 'bg-amber-950/80' : 'bg-amber-900/30 hover:bg-amber-900/50',
                flashing === f.note && 'ring-2 ring-accent-bass ring-inset bg-accent-bass/20 glow-bass',
                remoteFlashing === f.note && flashing !== f.note && 'ring-2 ring-orange-400 ring-inset'
              ]"
            >
              <span class="text-sm font-medium text-amber-50">{{ f.label }}</span>
              <kbd
                v-if="f.key"
                class="text-[9px] mt-0.5 px-1 rounded bg-amber-950 text-amber-200/80 font-mono"
              >{{ f.key }}</kbd>
            </button>
          </div>
        </div>
        <!-- Position-marker dot under fret 3 (typical bass inlay) -->
        <div class="grid grid-cols-[2.5rem_repeat(5,1fr)] gap-1 mt-1">
          <div></div>
          <div></div>
          <div></div>
          <div></div>
          <div class="flex justify-center">
            <span class="size-1.5 rounded-full bg-amber-200/40"></span>
          </div>
          <div></div>
        </div>
      </div>
    </div>
  </div>
</template>
