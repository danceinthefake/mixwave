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

import { ref, toRef } from "vue"
import { useLiveVue } from "live_vue"
import "@/lib/audio/kendang"
import { ensureStarted, play, stopAll } from "@/lib/audio"
import { useInstrumentFlash, useInstrumentKeyboard } from "@/lib/instrument"

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

const kendangNames = new Set<KendangSound>(["dang", "tut", "dut", "tak", "tung", "pak"])

const {
  local: flashing,
  remote: remoteFlashing,
  flash,
} = useInstrumentFlash<KendangSound>({
  remoteHit: toRef(props, "remoteHit"),
  instrument: "kendang",
  extractRemote: (hit) =>
    kendangNames.has(hit.note as KendangSound) ? (hit.note as KendangSound) : null,
})

async function hit(name: KendangSound) {
  await ensureStarted()
  play("kendang", style.value, name)
  flash(name)
  const label = pads.find((p) => p.name === name)?.label ?? name
  live.pushEvent("note", { instrument: "kendang", style: style.value, note: name, label })
}

function selectStyle(id: KendangStyle) {
  if (id === style.value) return
  stopAll("kendang", style.value)
  style.value = id
}

useInstrumentKeyboard({
  findByKey: (k) => pads.find((p) => p.key === k),
  onDown: (p) => hit(p.name),
})
</script>

<template>
  <div class="space-y-4">
    <!-- Style selector -->
    <div class="flex items-center gap-1">
      <span class="text-xs uppercase tracking-wider text-muted-foreground mr-2"> Style </span>
      <button
        v-for="s in styles"
        :key="s.id"
        @click="selectStyle(s.id)"
        :aria-pressed="style === s.id"
        :class="[
          'px-3 py-1 text-xs rounded-md border transition-colors',
          style === s.id
            ? 'bg-accent-kendang text-background border-accent-kendang'
            : 'bg-card hover:bg-accent text-muted-foreground border-input',
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
        :aria-label="`${p.label}${p.key ? ' (press ' + p.key + ')' : ''}`"
        :class="[
          'pad-touch touch-manipulation aspect-[3/2] rounded-lg border flex flex-col items-center justify-center gap-1 transition-all active:scale-95 hover:bg-accent',
          i < 3 ? 'bg-card' : 'bg-muted',
          flashing === p.name && 'ring-4 ring-accent-kendang scale-95 glow-kendang',
          remoteFlashing === p.name && flashing !== p.name && 'ring-4 ring-orange-400',
        ]"
      >
        <div class="text-lg font-bold font-display">{{ p.label }}</div>
        <kbd
          class="hidden sm:inline-block text-[10px] px-1.5 py-0.5 rounded bg-muted text-muted-foreground font-mono"
        >
          {{ p.key }}
        </kbd>
      </button>
    </div>
  </div>
</template>
