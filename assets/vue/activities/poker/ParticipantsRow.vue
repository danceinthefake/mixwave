<script setup lang="ts">
// Row of participant avatars + their voted-status indicator. Card
// silhouette appears once the user votes; on reveal, the silhouette
// flips to show the value. See features/planning-poker.md §5.

import { computed } from "vue"
import type { Participant, PokerStatus } from "./PokerBoard.vue"

const props = defineProps<{
  participants: Participant[]
  status: PokerStatus
  // Drives the card-flip transform. PokerBoard lags this behind
  // `status === "revealed"` by ~800ms so the chime + suspense moment
  // land before the cards turn. Late joiners see flipped=true
  // immediately, no suspense, since they missed the moment anyway.
  flipped: boolean
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

// "Waiting on …" nudge. Shows during :voting once at least one
// person has voted, listing whoever's left. Names up to three;
// past that, a count keeps the hint from sprawling. Self renders
// as "you" so the user can tell when they're the holdup —
// otherwise their own alias would appear and read like a stranger
// in the third person.
const waitingHint = computed<string | null>(() => {
  if (props.status !== "voting") return null
  if (votedCount.value === 0) return null
  const nonVoters = props.participants.filter((p) => !hasVoted(p.user_id))
  if (nonVoters.length === 0) return null

  const names = nonVoters.map((p) =>
    p.user_id === props.current_user_id ? "you" : displayName(p),
  )
  if (names.length === 1) return `Waiting on ${names[0]}`
  if (names.length === 2) return `Waiting on ${names[0]} and ${names[1]}`
  if (names.length === 3) return `Waiting on ${names[0]}, ${names[1]}, and ${names[2]}`
  return `Waiting on ${names.length} players`
})

// True for an unvoted silhouette once someone else has voted —
// drops its opacity harder than the baseline empty state so the
// eye reads "explicitly missing" rather than "round hasn't really
// started yet". Returns false at round start (nobody's behind
// when nobody's voted) and during :revealed (the conversation
// has moved on).
function isOverdue(userId: string): boolean {
  return (
    props.status === "voting" &&
    votedCount.value > 0 &&
    !hasVoted(userId)
  )
}
</script>

<template>
  <div class="space-y-2">
    <!-- Label + voted count stacked + centered. The flex row with
         justify-between was anchored to the section's left and right
         edges; centered stack puts the label at the head of a
         centered column with the silhouettes below. -->
    <div class="text-center space-y-0.5">
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        Players
      </p>
      <p class="text-xs text-muted-foreground tabular-nums">
        {{ votedCount }} / {{ participants.length }} voted
      </p>
      <!-- Nudge appears only once at least one vote is in and at
           least one teammate hasn't. Stays a small italic hint
           rather than a banner — it's a gentle pointer, not a
           call-out. -->
      <p
        v-if="waitingHint"
        class="text-xs italic text-muted-foreground/90 pt-0.5"
      >
        {{ waitingHint }}
      </p>
    </div>
    <ul class="flex flex-wrap gap-3 justify-center">
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
            flipped && hasVoted(p.user_id) && 'is-revealed',
            isOverdue(p.user_id) && 'is-overdue',
          ]"
          :aria-label="
            !hasVoted(p.user_id)
              ? `${displayName(p)} hasn't voted`
              : flipped
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
  transition: opacity 200ms ease-out;
}

/* Empty silhouette while at least one teammate HAS voted — dims
   harder so the eye reads "explicitly missing" rather than "round
   hasn't really started yet". Pairs with the "Waiting on …" hint
   above the row. Layered onto .is-empty (which already styled
   the dashed hatched look). */
.card-silhouette.is-empty.is-overdue {
  opacity: 0.4;
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
