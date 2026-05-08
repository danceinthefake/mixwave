<script setup lang="ts">
// Drum pad — laid out as a full kit from the drummer's top-down
// perspective, with all the pieces a typical rock kit ships with:
//
//   2 crash cymbals (left, right)         ← upper corners
//   3 toms (small, mid, floor)            ← mounted small/mid above
//                                            the bass drum, floor
//                                            tom on the lower right
//   1 ride cymbal                          ← upper right
//   1 bass drum + foot pedal               ← centre column
//   1 hi-hat (closed + open) + foot pedal  ← left side
//   1 snare                                ← lower centre
//   1 throne                                ← drummer's seat, decorative
//
// 11 playable pads. Hi-Hat Pedal and Throne are visual-only — they
// complete the kit picture without adding extra triggers.
//
// Keyboard shortcuts mirror each pad's horizontal position in the
// kit, so the QWERTY column you press matches where the pad sits
// from left to right:
//
//   q .  . r t y . . o .       ← Crash 1, Sm Tom, Bass, Mid Tom, Ride
//   a s . . . . . . l .         ← Hi-hat, Open, ...,  Crash 2
//   z . . v b . m               ← HH Pedal, Snare, Bass Pedal, Floor Tom
//
// Bass Drum and Bass Pedal both trigger `kick` — two ways to play
// the same drum, like a double-pedal setup. Both crash pads
// trigger `crash`. Remote players hear one of each regardless of
// which trigger the sender used.
//
// Local audio plays immediately on tap; the note + the player's
// chosen style are pushed to LiveView for broadcast. Remote players
// hear *the sender's* style — coherent kit sound for everyone in
// the jam.

import { onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll, type DrumName } from "@/lib/audio"

const props = defineProps<{
  remoteHit: { instrument: string; note: string; t: number } | null
}>()

const live = useLiveVue()

type DrumStyle = "synth" | "808" | "acoustic"
// Each visible pad has its own `id` (so two crashes don't flash
// each other on local taps) and a `drum` (the actual sound to
// trigger; null for purely-decorative pieces like the throne or
// hi-hat foot pedal). The `pos` is a percentage box inside the
// kit container, painting each piece where it would sit on a
// real kit.
type Pad = {
  id: string
  drum: DrumName | null
  label: string
  key: string | null
  pos: { left: string; top: string; width: string; height: string }
  shape: "round" | "square" | "oval"
}
type StyleOption = { id: DrumStyle; label: string }

const styles: StyleOption[] = [
  { id: "synth", label: "Synth" },
  { id: "808", label: "808" },
  { id: "acoustic", label: "Acoustic" },
]

const style = ref<DrumStyle>("synth")

const pads: Pad[] = [
  // Top row: outer crashes + mounted toms + ride.
  {
    id: "crash_l",
    drum: "crash",
    label: "Crash 1",
    key: "q",
    pos: { left: "1%", top: "2%", width: "16%", height: "22%" },
    shape: "round",
  },
  {
    id: "tom_high",
    drum: "tom_high",
    label: "Sm Tom",
    key: "r",
    pos: { left: "31%", top: "5%", width: "13%", height: "20%" },
    shape: "round",
  },
  {
    id: "tom_mid",
    drum: "tom_mid",
    label: "Mid Tom",
    key: "y",
    pos: { left: "47%", top: "5%", width: "13%", height: "20%" },
    shape: "round",
  },
  {
    id: "ride",
    drum: "ride",
    label: "Ride",
    key: "o",
    pos: { left: "82%", top: "2%", width: "16%", height: "22%" },
    shape: "round",
  },
  // Bass drum just below the mounted toms — large round at centre.
  {
    id: "kick_drum",
    drum: "kick",
    label: "Bass",
    key: "t",
    pos: { left: "37%", top: "27%", width: "23%", height: "22%" },
    shape: "round",
  },
  // Hi-hat pair on the left, second crash on the right.
  {
    id: "hihat",
    drum: "hihat",
    label: "Hi-hat",
    key: "a",
    pos: { left: "2%", top: "50%", width: "13%", height: "17%" },
    shape: "round",
  },
  {
    id: "open_hat",
    drum: "open_hat",
    label: "Open",
    key: "s",
    pos: { left: "16%", top: "50%", width: "13%", height: "17%" },
    shape: "round",
  },
  {
    id: "crash_r",
    drum: "crash",
    label: "Crash 2",
    key: "l",
    pos: { left: "82%", top: "48%", width: "16%", height: "20%" },
    shape: "round",
  },
  // Snare lower-centre, floor tom lower-right.
  {
    id: "snare",
    drum: "snare",
    label: "Snare",
    key: "v",
    pos: { left: "26%", top: "68%", width: "18%", height: "19%" },
    shape: "round",
  },
  {
    id: "tom_floor",
    drum: "tom_floor",
    label: "Floor Tom",
    key: "m",
    pos: { left: "55%", top: "65%", width: "21%", height: "23%" },
    shape: "round",
  },
  // Pedals + throne along the bottom. Hi-hat pedal triggers the
  // foot-chick voice — quieter and tighter than the closed-stick
  // hi-hat. Throne stays decorative (no drum kit has a "throne
  // sound").
  {
    id: "hihat_pedal",
    drum: "hihat_pedal",
    label: "HH Pedal",
    key: "z",
    pos: { left: "5%", top: "88%", width: "11%", height: "8%" },
    shape: "square",
  },
  {
    id: "kick_pedal",
    drum: "kick",
    label: "Bass Pedal",
    key: "b",
    pos: { left: "40%", top: "85%", width: "16%", height: "10%" },
    shape: "square",
  },
  {
    id: "throne",
    drum: null,
    label: "Throne",
    key: null,
    pos: { left: "44%", top: "96%", width: "10%", height: "4%" },
    shape: "oval",
  },
]

// `flashing` is keyed by pad id (so tapping Crash 1 doesn't ring
// both crashes); `remoteFlashing` is keyed by drum name (the
// network sends only the drum, so both pads of a doubled piece
// flash on a remote hit).
const flashing = ref<string | null>(null)
const remoteFlashing = ref<DrumName | null>(null)
let flashTimer: number | null = null
let remoteFlashTimer: number | null = null

function flash(padId: string) {
  flashing.value = padId
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashing.value = null), 120)
}

function flashRemote(name: DrumName) {
  remoteFlashing.value = name
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  // Slightly longer than local so it's visible even after a short network hop.
  remoteFlashTimer = window.setTimeout(() => (remoteFlashing.value = null), 200)
}

const drumNames = new Set<DrumName>([
  "kick",
  "snare",
  "hihat",
  "open_hat",
  "hihat_pedal",
  "crash",
  "ride",
  "tom_high",
  "tom_mid",
  "tom_floor",
])

watch(
  () => props.remoteHit,
  (hit) => {
    if (!hit || hit.instrument !== "drums") return
    if (drumNames.has(hit.note as DrumName)) flashRemote(hit.note as DrumName)
  },
)

async function hit(pad: Pad) {
  // Decorative pads (throne, hi-hat foot pedal) have no drum
  // attached and don't make sound when tapped.
  if (!pad.drum) return
  await ensureStarted()
  play("drums", style.value, pad.drum)
  flash(pad.id)
  live.pushEvent("note", { instrument: "drums", style: style.value, note: pad.drum })
}

function selectStyle(id: DrumStyle) {
  if (id === style.value) return
  // Cut any tail still ringing on the previous flavor before switching.
  stopAll("drums", style.value)
  style.value = id
}

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  const pad = pads.find((p) => p.key === event.key)
  if (pad) {
    event.preventDefault()
    hit(pad)
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
  stopAll("drums", style.value)
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

    <!-- Kit canvas. Aspect-ratio keeps the layout proportional at any
         width; on narrow screens it just gets smaller, not crushed. -->
    <div
      class="relative w-full mx-auto"
      style="max-width: 720px; aspect-ratio: 4 / 3;"
    >
      <button
        v-for="p in pads"
        :key="p.id"
        @pointerdown.prevent="hit(p)"
        :disabled="!p.drum"
        :style="{
          left: p.pos.left,
          top: p.pos.top,
          width: p.pos.width,
          height: p.pos.height,
        }"
        :class="[
          'absolute border flex flex-col items-center justify-center gap-1 select-none transition-all',
          p.shape === 'round'
            ? 'rounded-full'
            : p.shape === 'oval'
              ? 'rounded-full'
              : 'rounded-lg',
          p.drum
            ? 'bg-card hover:bg-accent active:scale-95 cursor-pointer'
            : 'bg-muted/40 text-muted-foreground/60 cursor-default',
          flashing === p.id && 'ring-4 ring-primary scale-95',
          remoteFlashing === p.drum && flashing !== p.id && 'ring-4 ring-orange-400'
        ]"
      >
        <div class="text-xs font-medium">{{ p.label }}</div>
        <kbd
          v-if="p.key"
          class="text-[10px] px-1 py-0.5 rounded bg-muted text-muted-foreground"
        >{{ p.key }}</kbd>
      </button>
    </div>
  </div>
</template>
