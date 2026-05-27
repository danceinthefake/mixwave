<script setup lang="ts">
// Host-only controls (features/mini-game.md §1). Phase-dependent:
// lobby → Start (gated <2 players); turn → Skip; reveal → Next;
// gameover → Play again / End. Rendered in the board header only
// when `is_host`.

import { computed } from "vue"
import type { MiniGamePhase } from "./MiniGameBoard.vue"

const props = defineProps<{
  phase: MiniGamePhase
  player_count: number
  min_players: number
}>()

defineEmits<{
  start: []
  skip: []
  next: []
  "play-again": []
  end: []
}>()

const canStart = computed(() => props.player_count >= props.min_players)

const primaryBtn =
  "px-3 py-1.5 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 hover:-translate-y-px hover:shadow-md transition-all cursor-pointer font-medium disabled:opacity-50 disabled:cursor-not-allowed disabled:hover:translate-y-0 disabled:hover:shadow-none"
const secondaryBtn =
  "px-3 py-1.5 text-sm rounded-md border bg-card hover:bg-accent text-foreground cursor-pointer font-medium transition-colors"
</script>

<template>
  <div class="flex items-center gap-2">
    <!-- Start is gated <2 players; the lobby column explains why, so
         no duplicate hint here. -->
    <button
      v-if="phase === 'lobby'"
      type="button"
      :disabled="!canStart"
      @click="$emit('start')"
      :class="primaryBtn"
    >
      Start game
    </button>

    <button v-else-if="phase === 'turn'" type="button" @click="$emit('skip')" :class="secondaryBtn">
      Skip turn
    </button>

    <button
      v-else-if="phase === 'turn_reveal'"
      type="button"
      @click="$emit('next')"
      :class="primaryBtn"
    >
      Next
    </button>

    <template v-else-if="phase === 'gameover'">
      <button type="button" @click="$emit('play-again')" :class="primaryBtn">Play again</button>
      <button type="button" @click="$emit('end')" :class="secondaryBtn">End</button>
    </template>
  </div>
</template>
