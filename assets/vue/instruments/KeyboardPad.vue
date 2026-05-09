<script setup lang="ts">
// Keyboard pad — three octaves of piano keys visible at once, plus
// the high C that closes the top octave (22 white + 15 black keys).
// Click any key, or use the full QWERTY shortcut grid:
//
//   Lower octave (z-row):  whites z x c v b n m, blacks s d g h j
//                          (blacks sit on home-row letters between)
//   Middle octave (q-row): whites q w e r t y u, blacks 2 3 5 6 7
//                          (canonical Bitwig/Ableton mapping)
//   Upper octave:          whites i o p [ ] \ ', blacks 8 9 - = ;
//                          (right side of the keyboard; less spatial
//                          than the lower two but covers all 12)
//   Closing high C:        /
//
// Shifting the octave window with +/- moves all 3 visible octaves
// up or down together. The QWERTY mapping is fixed to the visible
// window — what you see is what you can play.
//
// PolySynth lets multiple keys ring at once. JamReceiver handles
// remote players' notes — pads only push.

import { computed, onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll, preload } from "@/lib/audio"
import { FLASH_MS, REMOTE_FLASH_DELTA_MS } from "@/lib/motion"

const props = defineProps<{
  remoteHit: { instrument: string; note: string; t: number } | null
}>()

const live = useLiveVue()

type KeyboardStyle = "synth" | "lead" | "piano"
type StyleOption = { id: KeyboardStyle; label: string }

const styles: StyleOption[] = [
  { id: "synth", label: "Synth" },
  { id: "lead", label: "Lead" },
  { id: "piano", label: "Grand" },
]

const style = ref<KeyboardStyle>("synth")

// Lowest visible octave. Default 3 → visible C3..C6 (three full
// octaves + the closing high C). Range capped so the visible window
// always stays inside what the engines can render cleanly.
const baseOctave = ref(3)
const OCTAVE_MIN = 1
const OCTAVE_MAX = 5
const VISIBLE_OCTAVES = 3

type WhiteKey = { note: string; key: string; label: string; octave: number }
type BlackKey = {
  note: string
  key: string
  label: string
  afterIdx: number
  octave: number
}

// QWERTY shortcuts for every visible key. 22 whites + 15 blacks +
// 1 closing C = 38 keys, mapped row-by-row across the keyboard.
const WHITE_KEY_SHORTCUTS: ReadonlyArray<string> = [
  // Lower octave (7) — z-row
  "z", "x", "c", "v", "b", "n", "m",
  // Middle octave (7) — q-row
  "q", "w", "e", "r", "t", "y", "u",
  // Upper octave (7) — right-side mix (i/o/p brackets backslash apostrophe)
  "i", "o", "p", "[", "]", "\\", "'",
  // Closing high C
  "/",
]
const BLACK_KEY_SHORTCUTS: ReadonlyArray<string> = [
  // Lower octave blacks — home-row letters between z-row whites
  "s", "d", "g", "h", "j",
  // Middle octave blacks — number-row between q-row whites
  "2", "3", "5", "6", "7",
  // Upper octave blacks — right-side number row + ;
  "8", "9", "-", "=", ";",
]

// 22 white keys: 7 naturals × 3 octaves + the closing C of the next
// octave. Each gets a QWERTY shortcut from WHITE_KEY_SHORTCUTS.
const whiteKeys = computed<WhiteKey[]>(() => {
  const naturals = ["C", "D", "E", "F", "G", "A", "B"] as const
  const result: WhiteKey[] = []
  for (let octIdx = 0; octIdx < VISIBLE_OCTAVES; octIdx++) {
    const oct = baseOctave.value + octIdx
    for (const n of naturals) {
      result.push({ note: `${n}${oct}`, label: n, key: "", octave: oct })
    }
  }
  result.push({
    note: `C${baseOctave.value + VISIBLE_OCTAVES}`,
    label: "C",
    key: "",
    octave: baseOctave.value + VISIBLE_OCTAVES,
  })
  for (let i = 0; i < result.length && i < WHITE_KEY_SHORTCUTS.length; i++) {
    result[i].key = WHITE_KEY_SHORTCUTS[i]
  }
  return result
})

// 15 black keys: 5 sharps × 3 octaves, positioned BETWEEN white
// keys. afterIdx is the white-key index this black sits to the
// right of. Each gets a QWERTY shortcut from BLACK_KEY_SHORTCUTS.
const blackKeys = computed<BlackKey[]>(() => {
  const blacks = [
    { label: "C#", afterInOctave: 0 },
    { label: "D#", afterInOctave: 1 },
    { label: "F#", afterInOctave: 3 },
    { label: "G#", afterInOctave: 4 },
    { label: "A#", afterInOctave: 5 },
  ]
  const result: BlackKey[] = []
  for (let octIdx = 0; octIdx < VISIBLE_OCTAVES; octIdx++) {
    const oct = baseOctave.value + octIdx
    for (const b of blacks) {
      result.push({
        note: `${b.label}${oct}`,
        label: b.label,
        key: "",
        afterIdx: octIdx * 7 + b.afterInOctave,
        octave: oct,
      })
    }
  }
  for (let i = 0; i < result.length && i < BLACK_KEY_SHORTCUTS.length; i++) {
    result[i].key = BLACK_KEY_SHORTCUTS[i]
  }
  return result
})

function shiftOctave(delta: number) {
  const next = baseOctave.value + delta
  if (next < OCTAVE_MIN || next > OCTAVE_MAX) return
  // Cut held notes from the previous window so they don't stick.
  stopAll("keyboard", style.value)
  baseOctave.value = next
}

const flashingNote = ref<string | null>(null)
const remoteFlashingNote = ref<string | null>(null)
let flashTimer: number | null = null
let remoteFlashTimer: number | null = null

function flash(note: string) {
  flashingNote.value = note
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashingNote.value = null), FLASH_MS.medium)
}

function flashRemote(note: string) {
  remoteFlashingNote.value = note
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  remoteFlashTimer = window.setTimeout(
    () => (remoteFlashingNote.value = null),
    FLASH_MS.medium + REMOTE_FLASH_DELTA_MS,
  )
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
  stopAll("keyboard", style.value)
  style.value = id
  preload("keyboard", id)
}

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  const all = [...whiteKeys.value, ...blackKeys.value]
  const k = all.find((x) => x.key === event.key)
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
  stopAll("keyboard", style.value)
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
              ? 'bg-accent-keyboard text-background border-accent-keyboard'
              : 'bg-card hover:bg-accent text-muted-foreground border-input'
          ]"
        >
          {{ s.label }}
        </button>
      </div>

      <!-- Octave shift -->
      <div class="flex items-center gap-1 ml-auto">
        <span class="text-xs uppercase tracking-wider text-muted-foreground mr-2">Oct</span>
        <button
          @click="shiftOctave(-1)"
          :disabled="baseOctave <= OCTAVE_MIN"
          class="px-2 py-1 text-xs rounded-md border bg-card hover:bg-accent text-muted-foreground border-input disabled:opacity-30 disabled:cursor-not-allowed"
        >
          −
        </button>
        <span class="text-sm tabular-nums font-mono w-20 text-center">
          C{{ baseOctave }}–C{{ baseOctave + VISIBLE_OCTAVES }}
        </span>
        <button
          @click="shiftOctave(1)"
          :disabled="baseOctave >= OCTAVE_MAX"
          class="px-2 py-1 text-xs rounded-md border bg-card hover:bg-accent text-muted-foreground border-input disabled:opacity-30 disabled:cursor-not-allowed"
        >
          +
        </button>
      </div>
    </div>

    <!-- Keyboard. Three octaves at a generous min-width so each
         white key clears the WCAG touch target on mobile (~50 px).
         Horizontal scroll for the part that doesn't fit; soft edge
         fades hint that there's more to swipe to. -->
    <div class="relative -mx-2">
      <!-- Edge fade overlays. pointer-events-none so they never
           intercept taps on the keys underneath. Hidden on lg+
           where the whole keyboard usually fits without scroll. -->
      <div class="pointer-events-none absolute inset-y-0 left-0 w-6 z-10 bg-gradient-to-r from-background to-transparent lg:hidden"></div>
      <div class="pointer-events-none absolute inset-y-0 right-0 w-6 z-10 bg-gradient-to-l from-background to-transparent lg:hidden"></div>

      <div class="overflow-x-auto px-2">
        <!-- min-width sized so each white key is at least ~50 px on
             mobile (1100 / 22 ≈ 50). Black keys overlay at w-9 = 36 px;
             both are much friendlier to thumbs than the previous
             720 / 28 px sizing. -->
        <div class="relative h-44 select-none mx-auto" style="min-width: 1100px;">
          <!-- white keys -->
          <div class="absolute inset-0 flex">
            <button
              v-for="key in whiteKeys"
              :key="key.note"
              @pointerdown.prevent="hit(key.note)"
              :class="[
                'flex-1 border rounded-b-md flex flex-col items-center justify-end pb-2 transition-all touch-none',
                flashingNote === key.note
                  ? 'bg-accent-keyboard text-background border-accent-keyboard glow-keyboard'
                  : remoteFlashingNote === key.note
                    ? 'bg-orange-100 text-orange-900 border-orange-400'
                    : 'bg-white text-slate-700 hover:bg-slate-100 active:bg-slate-200'
              ]"
            >
              <span class="text-[11px] text-slate-400 leading-none mb-1">
                {{ key.label }}{{ key.octave }}
              </span>
              <kbd
                v-if="key.key"
                class="hidden sm:inline-block text-[10px] px-1 py-0.5 rounded bg-slate-200 text-slate-600 font-mono"
              >{{ key.key }}</kbd>
              <span v-else class="hidden sm:block text-[10px] h-4">&nbsp;</span>
            </button>
          </div>
          <!-- black keys overlay. Width derives from total white-key
               count so positions stay correct as the layout flexes.
               1.125rem = half of w-9 = horizontal centring offset. -->
          <button
            v-for="bk in blackKeys"
            :key="bk.note"
            @pointerdown.prevent.stop="hit(bk.note)"
            :style="{ left: `calc(${(bk.afterIdx + 1) * (100 / whiteKeys.length)}% - 1.125rem)` }"
            :class="[
              'absolute top-0 w-9 h-28 rounded-b-md border border-black flex flex-col items-center justify-end pb-2 transition-all touch-none',
              flashingNote === bk.note
                ? 'bg-accent-keyboard glow-keyboard'
                : remoteFlashingNote === bk.note
                  ? 'bg-orange-500'
                  : 'bg-slate-900 text-slate-200 hover:bg-slate-800 active:bg-slate-700'
            ]"
          >
            <kbd
              v-if="bk.key"
              class="hidden sm:inline-block mt-1 text-[9px] px-1 rounded bg-slate-700 text-slate-300 font-mono"
            >{{ bk.key }}</kbd>
          </button>
        </div>
      </div>
    </div>
  </div>
</template>
