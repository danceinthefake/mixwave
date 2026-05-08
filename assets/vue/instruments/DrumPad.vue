<script setup lang="ts">
// Drum pad — laid out as a real kit from the drummer's perspective:
//
//   1 hi-hat (one cymbal pair, played open or closed)
//   1 snare drum
//   2 crash cymbals (typical rock/metal kit)
//   1 kick drum with a double pedal — two trigger pads, both play
//     the same kick sound
//
// Seven pads total. Tap them or use keys 1–7. Both kick pads
// trigger the same `kick` drum so remote players hear one kick
// regardless of which foot pressed it; both crashes do the same.
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
// trigger). The `pos` is a percentage box inside the kit container,
// painting each piece where it would sit on a real kit.
type Pad = {
  id: string
  drum: DrumName
  label: string
  key: string
  pos: { left: string; top: string; width: string; height: string }
  shape: "round" | "square"
}
type StyleOption = { id: DrumStyle; label: string }

const styles: StyleOption[] = [
  { id: "synth", label: "Synth" },
  { id: "808", label: "808" },
  { id: "acoustic", label: "Acoustic" },
]

const style = ref<DrumStyle>("synth")

const pads: Pad[] = [
  // Cymbals across the top. Hi-hat pair on the left (drummer's left
  // hand), crash pair on the right.
  {
    id: "hihat",
    drum: "hihat",
    label: "Hi-hat",
    key: "1",
    pos: { left: "2%", top: "2%", width: "18%", height: "36%" },
    shape: "round",
  },
  {
    id: "open_hat",
    drum: "open_hat",
    label: "Open",
    key: "2",
    pos: { left: "22%", top: "5%", width: "18%", height: "36%" },
    shape: "round",
  },
  {
    id: "crash_l",
    drum: "crash",
    label: "Crash 1",
    key: "3",
    pos: { left: "58%", top: "2%", width: "18%", height: "36%" },
    shape: "round",
  },
  {
    id: "crash_r",
    drum: "crash",
    label: "Crash 2",
    key: "4",
    pos: { left: "78%", top: "5%", width: "18%", height: "36%" },
    shape: "round",
  },
  // Snare in the middle.
  {
    id: "snare",
    drum: "snare",
    label: "Snare",
    key: "5",
    pos: { left: "36%", top: "38%", width: "28%", height: "30%" },
    shape: "round",
  },
  // Double-pedal kick: two trigger pads, both play the same kick.
  {
    id: "kick_l",
    drum: "kick",
    label: "Kick L",
    key: "6",
    pos: { left: "20%", top: "70%", width: "28%", height: "28%" },
    shape: "square",
  },
  {
    id: "kick_r",
    drum: "kick",
    label: "Kick R",
    key: "7",
    pos: { left: "52%", top: "70%", width: "28%", height: "28%" },
    shape: "square",
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

const drumNames = new Set<DrumName>(["kick", "snare", "hihat", "open_hat", "crash"])

watch(
  () => props.remoteHit,
  (hit) => {
    if (!hit || hit.instrument !== "drums") return
    if (drumNames.has(hit.note as DrumName)) flashRemote(hit.note as DrumName)
  },
)

async function hit(pad: Pad) {
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
      style="max-width: 640px; aspect-ratio: 5 / 3;"
    >
      <button
        v-for="p in pads"
        :key="p.id"
        @pointerdown.prevent="hit(p)"
        :style="{
          left: p.pos.left,
          top: p.pos.top,
          width: p.pos.width,
          height: p.pos.height,
        }"
        :class="[
          'absolute border bg-card flex flex-col items-center justify-center gap-1 select-none transition-all active:scale-95 hover:bg-accent',
          p.shape === 'round' ? 'rounded-full' : 'rounded-lg',
          flashing === p.id && 'ring-4 ring-primary scale-95',
          remoteFlashing === p.drum && flashing !== p.id && 'ring-4 ring-orange-400'
        ]"
      >
        <div class="text-sm font-medium">{{ p.label }}</div>
        <kbd class="text-[10px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground">{{ p.key }}</kbd>
      </button>
    </div>
  </div>
</template>
