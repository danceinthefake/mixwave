<script setup lang="ts">
// Kendang — Indonesian two-headed hand drum, the rhythmic engine
// of dangdut. Six distinct tones laid out in a 2x3 grid:
//
//   Dang   Tut    Dut       open tones (low → high pitch)
//   Tak    Tung   Pak       slap, mid-open, closed slap
//
// Keyboard cluster mirrors the kit-shaped layout other pads use:
//   f g h    ← top row (Dang Tut Dut)
//   v b n    ← bottom row (Tak Tung Pak)

import { onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { ensureStarted, play, stopAll } from "@/lib/audio"
import { FLASH_MS, REMOTE_FLASH_DELTA_MS } from "@/lib/motion"

const props = defineProps<{
  remoteHit: { instrument: string; note: string; t: number } | null
}>()

const live = useLiveVue()

type KendangStyle = "synth" | "wood"
type StyleOption = { id: KendangStyle; label: string }

const styles: StyleOption[] = [
  { id: "synth", label: "Synth" },
  { id: "wood", label: "Wood" },
]

const style = ref<KendangStyle>("synth")

type KendangSound = "dang" | "tut" | "dut" | "tak" | "tung" | "pak"

type Pad = {
  name: KendangSound
  label: string
  key: string
}

const pads: Pad[] = [
  { name: "dang", label: "Dang", key: "f" },
  { name: "tut", label: "Tut", key: "g" },
  { name: "dut", label: "Dut", key: "h" },
  { name: "tak", label: "Tak", key: "v" },
  { name: "tung", label: "Tung", key: "b" },
  { name: "pak", label: "Pak", key: "n" },
]

const flashing = ref<KendangSound | null>(null)
const remoteFlashing = ref<KendangSound | null>(null)
let flashTimer: number | null = null
let remoteFlashTimer: number | null = null

function flash(name: KendangSound) {
  flashing.value = name
  if (flashTimer !== null) window.clearTimeout(flashTimer)
  flashTimer = window.setTimeout(() => (flashing.value = null), FLASH_MS.tight)
}

function flashRemote(name: KendangSound) {
  remoteFlashing.value = name
  if (remoteFlashTimer !== null) window.clearTimeout(remoteFlashTimer)
  remoteFlashTimer = window.setTimeout(
    () => (remoteFlashing.value = null),
    FLASH_MS.tight + REMOTE_FLASH_DELTA_MS,
  )
}

const kendangNames = new Set<KendangSound>([
  "dang",
  "tut",
  "dut",
  "tak",
  "tung",
  "pak",
])

watch(
  () => props.remoteHit,
  (hit) => {
    if (!hit || hit.instrument !== "kendang") return
    if (kendangNames.has(hit.note as KendangSound)) {
      flashRemote(hit.note as KendangSound)
    }
  },
)

async function hit(name: KendangSound) {
  await ensureStarted()
  play("kendang", style.value, name)
  flash(name)
  live.pushEvent("note", { instrument: "kendang", style: style.value, note: name })
}

function selectStyle(id: KendangStyle) {
  if (id === style.value) return
  stopAll("kendang", style.value)
  style.value = id
}

function onKey(event: KeyboardEvent) {
  if (event.repeat) return
  const p = pads.find((x) => x.key === event.key)
  if (p) {
    event.preventDefault()
    hit(p.name)
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
})
</script>

<template>
  <div class="space-y-4">
    <!-- Style selector -->
    <div class="flex items-center gap-1">
      <span class="text-xs uppercase tracking-wider text-muted-foreground mr-2">
        Style
      </span>
      <button
        v-for="s in styles"
        :key="s.id"
        @click="selectStyle(s.id)"
        :class="[
          'px-3 py-1 text-xs rounded-md border transition-colors',
          style === s.id
            ? 'bg-accent-kendang text-background border-accent-kendang'
            : 'bg-card hover:bg-accent text-muted-foreground border-input'
        ]"
      >
        {{ s.label }}
      </button>
    </div>

    <!-- Kendang pads, 2x3 grid. Open tones (top row) are slightly
         larger / use a warmer card background; slap variants (bottom)
         get a darker muted backing to read as percussive. -->
    <div class="grid grid-cols-3 gap-3 max-w-md mx-auto">
      <button
        v-for="(p, i) in pads"
        :key="p.name"
        @pointerdown.prevent="hit(p.name)"
        :class="[
          'aspect-[3/2] rounded-2xl border flex flex-col items-center justify-center gap-1 select-none transition-all active:scale-95 hover:bg-accent',
          i < 3 ? 'bg-card' : 'bg-muted',
          flashing === p.name && 'ring-4 ring-accent-kendang scale-95 glow-kendang',
          remoteFlashing === p.name && flashing !== p.name && 'ring-4 ring-orange-400'
        ]"
      >
        <div class="text-lg font-bold font-display">{{ p.label }}</div>
        <kbd class="text-[10px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground font-mono">
          {{ p.key }}
        </kbd>
      </button>
    </div>
  </div>
</template>
