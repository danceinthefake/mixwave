<script setup lang="ts">
// Shared scoreboard across all registry games (features/mini-game.md
// §8). A compact horizontal chip strip — reads as a top bar during a
// turn and a final ranking at game over. Sorted by points desc;
// highlights the current drawer and marks who's guessed this turn.

import { computed } from "vue"
import PlayerIdenticon from "./PlayerIdenticon.vue"

const props = defineProps<{
  scores: Record<string, number>
  players: string[]
  drawer_id: string | null
  guessed: string[]
  nameOf: (id: string | null) => string
  final?: boolean
}>()

// Everyone with a score plus everyone still in the rotation, even at
// zero — so the strip reads as the roster, not just "who's scored".
const rows = computed(() => {
  const ids = new Set<string>([...Object.keys(props.scores), ...props.players])
  const guessedSet = new Set(props.guessed)
  return [...ids]
    .map((id) => ({
      id,
      name: props.nameOf(id),
      points: props.scores[id] ?? 0,
      isDrawer: id === props.drawer_id,
      hasGuessed: guessedSet.has(id),
    }))
    .sort((a, b) => b.points - a.points || a.name.localeCompare(b.name))
})

const leaderId = computed(() => (rows.value.length ? rows.value[0].id : null))
</script>

<template>
  <ul
    class="flex flex-wrap items-center justify-center gap-2"
    :aria-label="final ? 'Final scores' : 'Scores'"
  >
    <li
      v-for="r in rows"
      :key="r.id"
      class="flex items-center gap-1.5 rounded-full border pl-1 pr-1 py-1 text-sm transition-colors"
      :class="
        r.isDrawer ? 'border-accent-minigame/50 bg-accent-minigame/10' : 'border-border bg-card/60'
      "
    >
      <PlayerIdenticon :seed="r.id" />
      <span v-if="final && r.id === leaderId" aria-hidden="true" title="Winner">👑</span>
      <span
        v-else-if="r.isDrawer"
        class="text-accent-minigame font-semibold"
        title="Drawing now"
        aria-hidden="true"
      >
        ✎
      </span>
      <span class="truncate max-w-[10rem]">{{ r.name }}</span>
      <span v-if="r.hasGuessed" class="text-accent-minigame" aria-hidden="true" title="Guessed it">
        ✓
      </span>
      <span
        class="ml-1 min-w-6 text-center tabular-nums font-semibold rounded-full bg-background/70 px-1.5 py-0.5 text-xs"
      >
        {{ r.points }}
      </span>
    </li>
  </ul>
</template>
