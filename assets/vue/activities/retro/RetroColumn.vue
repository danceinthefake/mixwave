<script setup lang="ts">
// One column. Renders a header + visible cards + (during
// :brainstorm) an add-card input. Total-count badge shows how
// many cards exist in the column overall — including others'
// hidden cards during brainstorm so the room can gauge pace.

import { computed, ref } from "vue"
import { useLiveVue } from "live_vue"
import RetroCard from "./RetroCard.vue"
import type {
  RetroColumnT,
  RetroCard as RetroCardT,
  RetroActionItem,
  RetroPhase,
} from "./RetroBoard.vue"

// Position-mapped subtle tint per column so the four lanes are
// visually distinguishable at a glance. Uses the activity-accent
// palette already loaded by Tailwind; /10 opacity keeps cards
// inside the column the dominant focus. Class strings are
// literal so Tailwind's source scan picks them up.
const COLUMN_TINTS = [
  "bg-accent-pad/10",
  "bg-accent-drums/10",
  "bg-accent-keyboard/10",
  "bg-accent-bass/10",
]
const COLUMN_HEADER_DOTS = [
  "bg-accent-pad",
  "bg-accent-drums",
  "bg-accent-keyboard",
  "bg-accent-bass",
]
// Closed-card placeholder uses the same accent as the column —
// "hidden card in this lane" reads as "lane colour, dimmed."
// /40 background + /60 border lands between the column-body
// /10 tint and a fully-saturated chip; reads as a physical
// card sitting in the column, not a glowing button.
const COLUMN_CLOSED_CARD_BG = [
  "bg-accent-pad/40",
  "bg-accent-drums/40",
  "bg-accent-keyboard/40",
  "bg-accent-bass/40",
]
const COLUMN_CLOSED_CARD_BORDER = [
  "border-accent-pad/60",
  "border-accent-drums/60",
  "border-accent-keyboard/60",
  "border-accent-bass/60",
]

const props = defineProps<{
  column: RetroColumnT
  cards: RetroCardT[]
  total_count: number
  // Number of cards from other participants whose contents are
  // hidden during :brainstorm. Rendered as face-down silhouettes
  // so the room can see at a glance that others are contributing.
  // Zero outside :brainstorm.
  hidden_count: number
  phase: RetroPhase
  is_host: boolean
  current_user_id: string
  tallies: Record<string, number>
  my_votes: Set<string>
  votes_remaining: number
  // Currently-focused card id during :discuss; passed through to
  // RetroCard so the highlight ring appears on the matching one.
  discussing_card_id: string | null
  // Action items grouped by their source_card_id. RetroCard
  // reads this to render its tied actions nested below the card
  // body during :discuss / :archived (spec §6).
  actions_by_card_id: Record<string, RetroActionItem[]>
  // Whether brainstorm cards are live-visible (host opted in
  // at :setup). Pass-through to RetroCard so reactions +
  // comments unlock during :brainstorm in that mode.
  brainstorm_visible: boolean
}>()

const live = useLiveVue()
const draft = ref("")

const tintClass = computed(() => COLUMN_TINTS[props.column.position] ?? "bg-card/40")
const dotClass = computed(() => COLUMN_HEADER_DOTS[props.column.position] ?? "bg-muted-foreground")
const closedCardBgClass = computed(() => COLUMN_CLOSED_CARD_BG[props.column.position] ?? "bg-muted")
const closedCardBorderClass = computed(
  () => COLUMN_CLOSED_CARD_BORDER[props.column.position] ?? "border-input",
)

function submit() {
  const body = draft.value.trim()
  if (!body) return
  live.pushEvent("retro_add_card", { column_id: props.column.id, body })
  draft.value = ""
}
</script>

<template>
  <section
    :class="['rounded-xl border flex flex-col', tintClass]"
    :aria-label="`Column: ${column.name}`"
  >
    <header class="flex items-center justify-between px-3 py-2.5 border-b">
      <div class="flex items-center gap-2">
        <span aria-hidden="true" :class="['size-2 rounded-full shrink-0', dotClass]"></span>
        <h2 class="text-sm font-semibold font-display tracking-tight">{{ column.name }}</h2>
      </div>
      <span
        v-if="total_count > 0"
        class="text-xs text-muted-foreground tabular-nums"
        :title="
          phase === 'brainstorm' ? 'Total cards (including others, hidden until reveal)' : 'Cards'
        "
      >
        {{ total_count }}
      </span>
    </header>

    <div class="p-2 space-y-2 min-h-32">
      <RetroCard
        v-for="card in cards"
        :key="card.id"
        :card="card"
        :phase="phase"
        :brainstorm_visible="brainstorm_visible"
        :is_mine="card.author_user_id === current_user_id"
        :current_user_id="current_user_id"
        :tally="tallies[card.id] ?? card.vote_count"
        :is_my_vote="my_votes.has(card.id)"
        :votes_remaining="votes_remaining"
        :is_host="is_host"
        :is_discussing="card.id === discussing_card_id"
        :tied_actions="actions_by_card_id[card.id] ?? []"
      />

      <!-- Face-down "card-back" placeholders for cards others
           have written but you can't see until :reveal. One per
           hidden card. Background colour matches the column's
           accent so each lane's hidden cards stay visually
           anchored to that column. -->
      <div
        v-for="n in hidden_count"
        :key="`hidden-${n}`"
        :class="['retro-card-back border', closedCardBgClass, closedCardBorderClass]"
        role="presentation"
        aria-label="Hidden card from another participant — reveals together"
        title="Someone added a card here — content reveals to everyone at the same time"
      ></div>

      <p
        v-if="phase === 'brainstorm' && cards.length === 0 && hidden_count === 0"
        class="text-xs text-muted-foreground italic text-center py-4"
      >
        Nothing here yet.
      </p>
    </div>

    <!-- Add-card input — :brainstorm only -->
    <form
      v-if="phase === 'brainstorm'"
      @submit.prevent="submit"
      class="p-2 border-t bg-background/40"
    >
      <textarea
        v-model="draft"
        maxlength="280"
        rows="2"
        :placeholder="`Add to ${column.name}…`"
        :aria-label="`Add card to ${column.name}`"
        class="w-full rounded-md border bg-card px-2.5 py-1.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        @keydown.enter.exact.prevent="submit"
      ></textarea>
      <div class="flex items-center justify-between pt-1.5 gap-2">
        <span class="text-[10px] text-muted-foreground tabular-nums"> {{ draft.length }}/280 </span>
        <button
          type="submit"
          :disabled="!draft.trim()"
          class="text-xs font-medium rounded-md bg-accent-bass text-background px-3 py-1 hover:bg-accent-bass/90 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          Add
        </button>
      </div>
    </form>
  </section>
</template>

<style scoped>
/* Sized to match a real RetroCard's typical single-line content
   height so the layout barely shifts when placeholders flip to
   real content at :reveal. Background + border colour come from
   Tailwind classes bound in the template (one accent per
   column position) so each lane keeps a consistent identity.
   Drop-shadow + inset shadow give the placeholder physical card
   depth — sitting on the column surface rather than painted in. */
.retro-card-back {
  border-radius: 0.5rem;
  height: 4.5rem;
  box-shadow:
    0 1px 3px rgba(0, 0, 0, 0.35),
    0 1px 2px rgba(0, 0, 0, 0.2),
    inset 0 1px 0 rgba(255, 255, 255, 0.06),
    inset 0 -2px 4px rgba(0, 0, 0, 0.18);
}
</style>
