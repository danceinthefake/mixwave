<script setup lang="ts">
// A player's geometric identicon — same deterministic pattern + hash
// colour the presence panel renders server-side, so identity carries
// across the chamber. Pure SVG, no network.

import { computed } from "vue"
import { identicon } from "@/lib/identicon"

const props = defineProps<{ seed: string }>()
const ico = computed(() => identicon(props.seed))
</script>

<template>
  <svg viewBox="0 0 5 5" class="rounded shrink-0 size-5" aria-hidden="true">
    <rect width="5" height="5" :fill="`oklch(0.93 0.03 ${ico.hue})`" />
    <rect
      v-for="([x, y], i) in ico.cells"
      :key="i"
      :x="x"
      :y="y"
      width="1.02"
      height="1.02"
      :fill="`oklch(0.58 0.19 ${ico.hue})`"
    />
  </svg>
</template>
