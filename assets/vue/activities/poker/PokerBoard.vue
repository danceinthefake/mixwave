<script setup lang="ts">
// Top-level Vue island for a planning-poker chamber. Mounted by
// Chamber.vue when `chamber.activity === "poker"`. Composes the
// five sub-components and routes events back to the LiveView via
// `useLiveVue().pushEvent`.
//
// State flows in from props (LV is the source of truth); user
// actions push back as Phoenix events. The LV's PokerSession
// GenServer broadcasts on every change, so every participant's
// PokerBoard re-renders within ~50 ms of any other participant's
// click.

import { computed, onMounted, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { playReveal } from "../../lib/audio"
import { isTypingInForm } from "../../lib/utils"
import StoryHeader from "./StoryHeader.vue"
import CardDeck from "./CardDeck.vue"
import ParticipantsRow from "./ParticipantsRow.vue"
import RevealPanel from "./RevealPanel.vue"
import HostControls from "./HostControls.vue"
import RoundHistory, { type HistoryEntry } from "./RoundHistory.vue"

export type PokerStatus = "voting" | "revealed"
export type DeckId = "fibonacci" | "modified_fibonacci" | "tshirt" | "pow2"

export type PokerSession = {
  status: PokerStatus
  deck: DeckId
  cards: string[]
  story: string | null
  round: number
  my_vote: string | null
  voted_user_ids: string[]
  votes: Record<string, string>
  history: HistoryEntry[]
  queue: string[]
}

export type Participant = {
  user_id: string
  display_name: string
  alias: string | null
}

const props = defineProps<{
  chamber_slug: string
  chamber_title?: string | null
  poker_session: PokerSession | null
  poker_participants: Participant[]
  current_user_id: string
  is_host: boolean
}>()

const live = useLiveVue()

// A poker chamber's GenServer always allocates a session at boot;
// `null` here only happens if Chamber.vue is mounted for a
// non-poker chamber by mistake. Render a clear empty state so we
// don't crash sub-components dereferencing `session.deck`.
const session = computed(() => props.poker_session)

// Card flip is staged from `session.status` by ~800ms so the
// reveal lands as a moment, not an instant truth-bomb. The cards
// hold face-down during the suspense window while the chime
// arpeggio plays (last note times with the flip). RevealPanel
// renders on the same beat so the verdict appears in sync with
// the cards turning. Late joiners and post-reload mounts skip the
// suspense — they missed the chime, and showing them face-down
// cards for 800ms would just look broken.
const REVEAL_SUSPENSE_MS = 800
const flipped = ref(false)
const reducedMotion =
  typeof window !== "undefined" &&
  typeof window.matchMedia === "function" &&
  window.matchMedia("(prefers-reduced-motion: reduce)").matches

watch(
  () => session.value?.status,
  (next, prev) => {
    if (next === "revealed" && prev === "voting") {
      if (reducedMotion) {
        flipped.value = true
        return
      }
      void playReveal()
      window.setTimeout(() => {
        flipped.value = true
      }, REVEAL_SUSPENSE_MS)
    } else if (next === "revealed") {
      flipped.value = true
    } else if (next === "voting") {
      flipped.value = false
    }
  },
  { immediate: true },
)

// True when the chamber is fresh and lonely — the host is alone,
// no votes have been cast, no story set. Renders an inline hint
// to share the link rather than staring at an empty player row
// in silence.
const isWaitingForTeam = computed(() => {
  if (!session.value) return false
  return (
    props.poker_participants.length <= 1 &&
    session.value.voted_user_ids.length === 0 &&
    session.value.status === "voting" &&
    !session.value.story
  )
})

function castVote(card: string) {
  if (!session.value || session.value.status !== "voting") return
  // Tapping the same card again withdraws — feels less awkward
  // than a separate "clear" button for the common "I misclicked"
  // case.
  if (session.value.my_vote === card) {
    live.pushEvent("poker_withdraw_vote", {})
  } else {
    live.pushEvent("poker_vote", { card })
  }
}

function reveal() {
  if (!props.is_host) return
  live.pushEvent("poker_reveal", {})
}

function revote() {
  if (!props.is_host) return
  live.pushEvent("poker_revote", {})
}

function nextRound(story?: string) {
  if (!props.is_host) return
  live.pushEvent("poker_next_round", story != null ? { story } : {})
}

function setStory(story: string) {
  if (!props.is_host) return
  live.pushEvent("poker_set_story", { story })
}

function setDeck(deck: DeckId) {
  if (!props.is_host) return
  live.pushEvent("poker_set_deck", { deck })
}

function setQueue(queue: string[]) {
  if (!props.is_host) return
  live.pushEvent("poker_set_queue", { queue })
}

// ── Keyboard shortcuts ──────────────────────────────────────────────
// Number keys 1-9 vote the card at that deck index (decks longer
// than 9 fall through — `100` / `?` / `☕` in modified_fibonacci
// are mouse-only since `?` and `☕` aren't impulsive votes anyway).
// Esc withdraws an already-cast vote. R / N / E drive the host-only
// reveal / next-round / re-vote flow so a power user can keep both
// hands on the keyboard during a long estimation session.
//
// Skips: events while typing in the story editor or alias input
// (handled by `isTypingInForm`), keys held with Ctrl/Cmd/Alt (so
// we don't steal browser shortcuts), and auto-repeat (no rapid-fire
// votes from a stuck key).
function handleKeyDown(event: KeyboardEvent) {
  if (event.repeat) return
  if (event.ctrlKey || event.metaKey || event.altKey) return
  if (isTypingInForm(event)) return
  if (!session.value) return

  const key = event.key

  // 1-9 → vote by deck index. Only during :voting.
  if (session.value.status === "voting" && /^[1-9]$/.test(key)) {
    const card = session.value.cards[Number(key) - 1]
    if (card !== undefined) {
      event.preventDefault()
      castVote(card)
      return
    }
  }

  // Esc → withdraw vote, if there's one to withdraw.
  if (key === "Escape") {
    if (session.value.status === "voting" && session.value.my_vote) {
      event.preventDefault()
      live.pushEvent("poker_withdraw_vote", {})
    }
    return
  }

  // Host-only actions below.
  if (!props.is_host) return
  const lower = key.toLowerCase()
  if (lower === "r" && session.value.status === "voting") {
    event.preventDefault()
    reveal()
  } else if (lower === "n" && session.value.status === "revealed") {
    event.preventDefault()
    nextRound()
  } else if (lower === "e" && session.value.status === "revealed") {
    event.preventDefault()
    revote()
  }
}

let keyController: AbortController | null = null
onMounted(() => {
  keyController = new AbortController()
  window.addEventListener("keydown", handleKeyDown, { signal: keyController.signal })
})
onUnmounted(() => {
  keyController?.abort()
})
</script>

<template>
  <section
    v-if="session"
    aria-label="Planning poker board"
    class="space-y-6"
  >
    <StoryHeader
      :story="session.story"
      :round="session.round"
      :queue_length="session.queue.length"
      :next_in_queue="session.queue[0] ?? null"
      :is_host="is_host"
      @update:story="setStory"
    />

    <ParticipantsRow
      :participants="poker_participants"
      :status="session.status"
      :flipped="flipped"
      :voted_user_ids="session.voted_user_ids"
      :votes="session.votes"
      :current_user_id="current_user_id"
    />

    <!-- Inline waiting-for-team hint. Renders only when the host is
         alone in a fresh chamber so it doesn't compete with a board
         that already has players or votes in it. Drops itself as
         soon as the team arrives. -->
    <p
      v-if="isWaitingForTeam"
      class="text-sm text-muted-foreground italic text-center"
    >
      Waiting for the team. Share the link to start.
    </p>

    <CardDeck
      v-if="session.status === 'voting'"
      :cards="session.cards"
      :selected="session.my_vote"
      @pick="castVote"
    />

    <Transition name="reveal-panel">
      <RevealPanel
        v-if="session.status === 'revealed' && flipped"
        :deck="session.deck"
        :cards="session.cards"
        :votes="session.votes"
        :participants="poker_participants"
      />
    </Transition>

    <HostControls
      v-if="is_host"
      :status="session.status"
      :deck="session.deck"
      :queue="session.queue"
      :has_votes="session.voted_user_ids.length > 0"
      @reveal="reveal"
      @revote="revote"
      @next-round="nextRound()"
      @change-deck="setDeck"
      @set-queue="setQueue"
    />

    <RoundHistory :history="session.history" />
  </section>

  <div v-else class="rounded-xl border bg-card/60 p-8 text-center text-muted-foreground">
    Poker session not ready yet.
  </div>
</template>

<style scoped>
/* Reveal panel fades in alongside the card flip. The 100ms delay
   lets the cards begin their rotateY before the verdict text
   resolves, so the eye reads "cards turning → answer arrives" as
   one beat rather than two competing animations. */
.reveal-panel-enter-active {
  transition:
    opacity 300ms ease-out 100ms,
    transform 300ms ease-out 100ms;
}
.reveal-panel-enter-from {
  opacity: 0;
  transform: translateY(8px);
}
.reveal-panel-enter-to {
  opacity: 1;
  transform: translateY(0);
}

/* Reduced motion: drop both delay and slide; the verdict still
   appears in sync with the (instant) card swap. */
@media (prefers-reduced-motion: reduce) {
  .reveal-panel-enter-active {
    transition: none;
  }
  .reveal-panel-enter-from,
  .reveal-panel-enter-to {
    transform: none;
  }
}
</style>
