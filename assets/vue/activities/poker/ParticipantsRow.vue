<script setup lang="ts">
// Row of participant avatars + their voted-status indicator. Card
// silhouette appears once the user votes; on reveal, the silhouette
// flips to show the value. See features/planning-poker.md §5.

import { computed } from "vue"
import type { Participant, PokerStatus } from "./PokerBoard.vue"

const props = defineProps<{
  participants: Participant[]
  status: PokerStatus
  voted_user_ids: string[]
  votes: Record<string, string>
  current_user_id: string
}>()

function hasVoted(userId: string): boolean {
  return props.voted_user_ids.includes(userId)
}

function voteValue(userId: string): string | undefined {
  return props.votes[userId]
}

function displayName(p: Participant): string {
  return p.alias?.trim() || p.display_name
}

const votedCount = computed(() => props.voted_user_ids.length)
</script>

<template>
  <div class="space-y-2">
    <div class="flex items-baseline justify-between">
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        Players
      </p>
      <p class="text-xs text-muted-foreground tabular-nums">
        {{ votedCount }} / {{ participants.length }} voted
      </p>
    </div>
    <ul class="flex flex-wrap gap-3">
      <li
        v-for="p in participants"
        :key="p.user_id"
        :class="[
          'flex flex-col items-center gap-2 min-w-24',
          p.user_id === current_user_id && 'opacity-100',
        ]"
      >
        <div
          :class="[
            'card-silhouette',
            hasVoted(p.user_id) ? 'is-voted' : 'is-empty',
            status === 'revealed' && hasVoted(p.user_id) && 'is-revealed',
          ]"
          :aria-label="
            !hasVoted(p.user_id)
              ? `${displayName(p)} hasn't voted`
              : status === 'revealed'
                ? `${displayName(p)} voted ${voteValue(p.user_id)}`
                : `${displayName(p)} has voted`
          "
        >
          <div class="card-face card-back" aria-hidden="true"></div>
          <div class="card-face card-front" aria-hidden="true">
            <span v-if="status === 'revealed'" class="font-bold font-display text-3xl">
              {{ voteValue(p.user_id) ?? "—" }}
            </span>
          </div>
        </div>
        <span
          class="text-sm text-foreground truncate max-w-24 text-center"
          :title="displayName(p)"
        >
          {{ displayName(p) }}
          <span v-if="p.user_id === current_user_id" class="text-muted-foreground">
            (you)
          </span>
        </span>
      </li>
    </ul>
  </div>
</template>

<style scoped>
/* Card silhouette: 80x112 rounded rect (5:7 playing-card
   proportions), flips on reveal via transform: rotateY(180deg).
   The "back" face is a gradient placeholder; the "front" face
   carries the numeric/string vote. */
.card-silhouette {
  position: relative;
  width: 5rem;
  height: 7rem;
  border-radius: 0.625rem;
  perspective: 900px;
  transform-style: preserve-3d;
  transition: transform 400ms cubic-bezier(0.4, 0.2, 0.2, 1);
}

.card-silhouette.is-empty {
  background: repeating-linear-gradient(
    45deg,
    var(--muted) 0,
    var(--muted) 6px,
    var(--card) 6px,
    var(--card) 12px
  );
  border: 2.5px dashed var(--muted-foreground);
  opacity: 0.7;
}

/* When empty, hide the back/front faces so the parent's dashed
   hatched pattern shows through. Without this, the card-back's
   gradient sits on top of the hatched pattern and covers it. */
.card-silhouette.is-empty .card-face {
  display: none;
}

.card-silhouette.is-voted {
  /* Pre-reveal "vote pending" border picks up --accent-poker so the
     vote-cast state reads as "in progress" (cyan = activity-poker
     accent); the post-reveal face-up state already carries the
     value at text-3xl, no border colour needed there. */
  border: 2.5px solid var(--accent-poker);
}

.card-silhouette.is-revealed {
  transform: rotateY(180deg);
}

.card-face {
  position: absolute;
  inset: 0;
  border-radius: 0.625rem;
  backface-visibility: hidden;
  display: flex;
  align-items: center;
  justify-content: center;
}

.card-back {
  /* Brand gradient (pink -> cyan -> green) matching the logo's
     horizontal stops, applied diagonally on the card so all three
     colours read along the card's longest axis. */
  background: linear-gradient(
    135deg,
    #e94886 0%,
    #56d2e6 50%,
    #b5e651 100%
  );
}

.card-front {
  background: var(--card);
  border: 1px solid var(--primary);
  transform: rotateY(180deg);
  color: var(--foreground);
}

/* prefers-reduced-motion: drop the flip animation, just swap. */
@media (prefers-reduced-motion: reduce) {
  .card-silhouette {
    transition: none;
  }
}
</style>
