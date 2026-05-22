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

import { computed } from "vue"
import { useLiveVue } from "live_vue"
import StoryHeader from "./StoryHeader.vue"
import CardDeck from "./CardDeck.vue"
import ParticipantsRow from "./ParticipantsRow.vue"
import RevealPanel from "./RevealPanel.vue"
import HostControls from "./HostControls.vue"

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
</script>

<template>
  <div v-if="session" class="space-y-6">
    <StoryHeader
      :story="session.story"
      :round="session.round"
      :is_host="is_host"
      @update:story="setStory"
    />

    <ParticipantsRow
      :participants="poker_participants"
      :status="session.status"
      :voted_user_ids="session.voted_user_ids"
      :votes="session.votes"
      :current_user_id="current_user_id"
    />

    <CardDeck
      v-if="session.status === 'voting'"
      :cards="session.cards"
      :selected="session.my_vote"
      @pick="castVote"
    />

    <RevealPanel
      v-else
      :deck="session.deck"
      :votes="session.votes"
      :participants="poker_participants"
    />

    <HostControls
      v-if="is_host"
      :status="session.status"
      :deck="session.deck"
      :has_votes="session.voted_user_ids.length > 0"
      @reveal="reveal"
      @next-round="nextRound()"
      @change-deck="setDeck"
    />
  </div>

  <div v-else class="rounded-2xl border bg-card/60 p-8 text-center text-muted-foreground">
    Poker session not ready yet.
  </div>
</template>
