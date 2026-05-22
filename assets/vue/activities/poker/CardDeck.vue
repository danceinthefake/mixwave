<script setup lang="ts">
// Vote picker. Renders the deck's card values as buttons; clicking
// one fires `pick(card)`. The currently-selected card is
// highlighted so the user can see what they voted at a glance —
// PokerBoard.vue treats a click on the selected card as a withdraw
// (toggle off).

defineProps<{
  cards: string[]
  selected: string | null
}>()

defineEmits<{ pick: [card: string] }>()
</script>

<template>
  <div class="space-y-2">
    <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
      Pick a card
    </p>
    <div class="flex flex-wrap gap-2">
      <button
        v-for="card in cards"
        :key="card"
        type="button"
        @click="$emit('pick', card)"
        :aria-pressed="card === selected"
        :class="[
          'pad-touch touch-manipulation min-h-12 min-w-12 px-3 py-2 rounded-lg text-base font-bold font-display border transition-all cursor-pointer',
          card === selected
            ? 'bg-primary text-primary-foreground border-primary shadow-md scale-105'
            : 'bg-card hover:bg-accent text-foreground border-input',
        ]"
      >
        {{ card }}
      </button>
    </div>
    <p v-if="selected" class="text-xs text-muted-foreground">
      Voted <span class="font-mono font-bold text-foreground">{{ selected }}</span> ·
      tap again to withdraw.
    </p>
  </div>
</template>
