<script setup lang="ts">
// Reveal panel: visible only when status === 'revealed'. Shows a
// per-value distribution plus stats. Numeric decks (fibonacci,
// modified_fibonacci, pow2) get average + median; the t-shirt
// deck gets mode only (per features/planning-poker.md §3).

import { computed } from "vue"
import type { DeckId, Participant } from "./PokerBoard.vue"

const props = defineProps<{
  deck: DeckId
  votes: Record<string, string>
  participants: Participant[]
}>()

const numericDecks: DeckId[] = ["fibonacci", "modified_fibonacci", "pow2"]

// Distribution: each unique vote value -> count of voters.
const distribution = computed(() => {
  const counts = new Map<string, number>()
  for (const v of Object.values(props.votes)) {
    counts.set(v, (counts.get(v) ?? 0) + 1)
  }
  return [...counts.entries()].sort((a, b) => b[1] - a[1])
})

// Numeric votes only — `?` and `☕` skipped. "½" → 0.5.
const numericValues = computed(() => {
  if (!numericDecks.includes(props.deck)) return []
  const out: number[] = []
  for (const v of Object.values(props.votes)) {
    if (v === "½") out.push(0.5)
    else {
      const n = Number(v)
      if (Number.isFinite(n)) out.push(n)
    }
  }
  return out
})

const average = computed(() => {
  if (numericValues.value.length === 0) return null
  const sum = numericValues.value.reduce((a, b) => a + b, 0)
  return sum / numericValues.value.length
})

const median = computed(() => {
  const xs = [...numericValues.value].sort((a, b) => a - b)
  if (xs.length === 0) return null
  const mid = Math.floor(xs.length / 2)
  return xs.length % 2 ? xs[mid] : (xs[mid - 1] + xs[mid]) / 2
})

const mode = computed(() => {
  if (distribution.value.length === 0) return null
  return distribution.value[0][0]
})

function format(n: number): string {
  return Number.isInteger(n) ? String(n) : n.toFixed(1)
}

const isNumericDeck = computed(() => numericDecks.includes(props.deck))
const totalVotes = computed(() => Object.keys(props.votes).length)
</script>

<template>
  <div class="space-y-3">
    <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
      Reveal
    </p>

    <div v-if="totalVotes === 0" class="text-sm text-muted-foreground italic">
      No votes were cast in this round.
    </div>

    <div v-else class="space-y-4">
      <!-- Distribution: each value with a bar showing its share. -->
      <ul class="space-y-1.5">
        <li
          v-for="[value, count] in distribution"
          :key="value"
          class="flex items-center gap-3"
        >
          <span class="w-10 font-mono font-bold text-base tabular-nums text-right">
            {{ value }}
          </span>
          <div class="flex-1 h-5 rounded-md bg-muted overflow-hidden">
            <div
              class="h-full bg-primary/60"
              :style="{ width: (count / totalVotes) * 100 + '%' }"
            ></div>
          </div>
          <span class="text-xs text-muted-foreground tabular-nums w-8">
            {{ count }}
          </span>
        </li>
      </ul>

      <!-- Stats: numeric decks get avg + median, t-shirt gets mode. -->
      <dl class="flex flex-wrap gap-x-6 gap-y-1 text-sm">
        <template v-if="isNumericDeck">
          <div v-if="average !== null" class="flex gap-1.5">
            <dt class="text-muted-foreground">Average:</dt>
            <dd class="font-bold font-mono">{{ format(average) }}</dd>
          </div>
          <div v-if="median !== null" class="flex gap-1.5">
            <dt class="text-muted-foreground">Median:</dt>
            <dd class="font-bold font-mono">{{ format(median) }}</dd>
          </div>
        </template>
        <div v-if="mode !== null" class="flex gap-1.5">
          <dt class="text-muted-foreground">Mode:</dt>
          <dd class="font-bold font-mono">{{ mode }}</dd>
        </div>
      </dl>
    </div>
  </div>
</template>
