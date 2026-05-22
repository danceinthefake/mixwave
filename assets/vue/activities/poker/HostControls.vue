<script setup lang="ts">
// Host-only controls: reveal / next-round + deck dropdown. The
// deck dropdown is disabled when `has_votes` is true — switching
// decks mid-vote would orphan whatever's already in the tally
// (see features/planning-poker.md §3). PokerBoard.vue v-if's this
// component on `is_host`.

import type { DeckId, PokerStatus } from "./PokerBoard.vue"

defineProps<{
  status: PokerStatus
  deck: DeckId
  has_votes: boolean
}>()

defineEmits<{
  reveal: []
  revote: []
  "next-round": []
  "change-deck": [deck: DeckId]
}>()

const deckLabels: Record<DeckId, string> = {
  fibonacci: "Fibonacci",
  modified_fibonacci: "Modified Fibonacci",
  tshirt: "T-shirt sizes",
  pow2: "Powers of 2",
}
</script>

<template>
  <div class="rounded-xl border bg-card/60 backdrop-blur-sm p-4 space-y-3">
    <div class="flex items-center justify-between gap-3">
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        Host controls
      </p>
      <div class="flex items-center gap-2">
        <button
          v-if="status === 'voting'"
          type="button"
          @click="$emit('reveal')"
          class="px-3 py-1.5 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 hover:-translate-y-px hover:shadow-md transition-all cursor-pointer font-medium"
        >
          Reveal
        </button>
        <template v-else>
          <button
            type="button"
            @click="$emit('revote')"
            class="px-3 py-1.5 text-sm rounded-md border bg-card hover:bg-accent text-foreground cursor-pointer font-medium transition-colors"
            title="Clear votes and let the team vote again on this same story"
          >
            Re-vote
          </button>
          <button
            type="button"
            @click="$emit('next-round')"
            class="px-3 py-1.5 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 hover:-translate-y-px hover:shadow-md transition-all cursor-pointer font-medium"
            title="Move on to the next story (round number advances)"
          >
            Next round
          </button>
        </template>
      </div>
    </div>

    <div class="flex items-center gap-2">
      <label for="poker-deck-select" class="text-xs text-muted-foreground">Deck</label>
      <select
        id="poker-deck-select"
        :value="deck"
        :disabled="has_votes"
        @change="(e) => $emit('change-deck', (e.target as HTMLSelectElement).value as DeckId)"
        class="px-2 py-1 text-xs rounded-md border bg-card text-foreground disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
      >
        <option v-for="(label, id) in deckLabels" :key="id" :value="id">
          {{ label }}
        </option>
      </select>
      <span v-if="has_votes" class="text-[11px] text-muted-foreground italic">
        Lock the round before switching decks.
      </span>
    </div>
  </div>
</template>
