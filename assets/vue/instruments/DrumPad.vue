<script setup lang="ts">
// Drum pad — laid out as a full kit from the drummer's top-down
// perspective, with all the pieces a typical rock kit ships with:
//
//   2 crash cymbals (left, right)         ← upper corners
//   3 toms (small, mid, floor)            ← mounted small/mid up
//                                            top, floor tom on the
//                                            lower right
//   1 ride cymbal                          ← upper right
//   1 hi-hat + foot pedal                  ← left side
//   1 snare                                ← lower centre
//   1 double bass pedal                    ← bottom centre, two
//                                            triggers for one kick
//   1 throne                                ← drummer's seat, decorative
//
// 11 playable pads. The bass drum isn't drawn — on a real kit it
// only sounds when the foot pedal beats it, never when struck by
// hand or stick, so there's nothing to click. The throne is
// visual-only — drum kits don't have a throne sound.
//
// Keyboard shortcuts cluster on the right of home position so
// both hands can play the whole kit without leaving the bar:
//
//   r t   u i             ← Crash 1, Sm Tom, Mid Tom, Ride
//   f g     j k           ← Hi-hat, Snare, Floor Tom, Crash 2
//      v b n              ← HH Pedal, Bass L, Bass R
//
// Bass L (`b`) and Bass R (`n`) both trigger `kick` — the actual
// double-pedal pattern, one trigger per foot. The Bass Drum
// visual at top-centre has no key; click it directly if you
// want to hit the drum from the top.
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
    key: "r",
    pos: { left: "1%", top: "2%", width: "16%", height: "26%" },
    shape: "round",
  },
  {
    id: "tom_high",
    drum: "tom_high",
    label: "Sm Tom",
    key: "t",
    pos: { left: "30%", top: "5%", width: "14%", height: "23%" },
    shape: "round",
  },
  {
    id: "tom_mid",
    drum: "tom_mid",
    label: "Mid Tom",
    key: "u",
    pos: { left: "46%", top: "5%", width: "14%", height: "23%" },
    shape: "round",
  },
  {
    id: "ride",
    drum: "ride",
    label: "Ride",
    key: "i",
    pos: { left: "82%", top: "2%", width: "16%", height: "26%" },
    shape: "round",
  },
  // No bass drum at the top centre. On a real kit the bass drum
  // isn't stick-played — only the foot pedals trigger it. The
  // pedals at the bottom (Bass L, Bass R) are the only kick
  // triggers in this UI for that reason.

  // Mid row of kit: hi-hat pair on the left, snare + floor tom in
  // the middle, second crash on the right. All four sit on the
  // home row of the keyboard for one-finger-per-pad reach.
  {
    id: "hihat",
    drum: "hihat",
    label: "Hi-hat",
    key: "f",
    pos: { left: "3%", top: "34%", width: "14%", height: "24%" },
    shape: "round",
  },
  {
    id: "snare",
    drum: "snare",
    label: "Snare",
    key: "g",
    pos: { left: "21%", top: "32%", width: "18%", height: "26%" },
    shape: "round",
  },
  {
    id: "tom_floor",
    drum: "tom_floor",
    label: "Floor Tom",
    key: "j",
    pos: { left: "53%", top: "30%", width: "22%", height: "28%" },
    shape: "round",
  },
  {
    id: "crash_r",
    drum: "crash",
    label: "Crash 2",
    key: "k",
    pos: { left: "83%", top: "32%", width: "14%", height: "26%" },
    shape: "round",
  },
  // Pedals + throne along the bottom. Hi-hat pedal triggers the
  // foot-chick voice. Two bass pedals (Bass L + Bass R) both
  // trigger `kick` for double-pedal patterns. Throne stays
  // decorative (no drum kit has a "throne sound").
  {
    id: "hihat_pedal",
    drum: "hihat_pedal",
    label: "HH Pedal",
    key: "v",
    pos: { left: "5%", top: "66%", width: "13%", height: "16%" },
    shape: "square",
  },
  {
    id: "kick_pedal_l",
    drum: "kick",
    label: "Bass L",
    key: "b",
    pos: { left: "33%", top: "64%", width: "15%", height: "20%" },
    shape: "square",
  },
  {
    id: "kick_pedal_r",
    drum: "kick",
    label: "Bass R",
    key: "n",
    pos: { left: "50%", top: "64%", width: "15%", height: "20%" },
    shape: "square",
  },
  {
    id: "throne",
    drum: null,
    label: "Throne",
    key: null,
    pos: { left: "42%", top: "90%", width: "16%", height: "8%" },
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

    <!-- Kit canvas. Aspect-ratio keeps the layout proportional at
         any width; on narrow screens it just gets smaller, not
         crushed. 5:3 with max-width 540 keeps the kit compact —
         no wasted space now that there's no bass drum at the
         centre and hi-hat/snare/floor-tom/crash-2 collapse onto a
         single mid row. -->
    <div
      class="relative w-full mx-auto"
      style="max-width: 540px; aspect-ratio: 5 / 3;"
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
