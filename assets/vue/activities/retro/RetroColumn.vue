<script setup lang="ts">
// One column. Renders a header + visible cards + (during
// :brainstorm) an add-card input. Total-count badge shows how
// many cards exist in the column overall — including others'
// hidden cards during brainstorm so the room can gauge pace.

import { computed, ref } from "vue"
import { useLiveVue } from "live_vue"
import RetroCard from "./RetroCard.vue"
import type { RetroColumnT, RetroCard as RetroCardT, RetroPhase } from "./RetroBoard.vue"

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
}>()

const live = useLiveVue()
const draft = ref("")

const tintClass = computed(
  () => COLUMN_TINTS[props.column.position] ?? "bg-card/40",
)
const dotClass = computed(
  () => COLUMN_HEADER_DOTS[props.column.position] ?? "bg-muted-foreground",
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
        <span
          aria-hidden="true"
          :class="['size-2 rounded-full shrink-0', dotClass]"
        ></span>
        <h2 class="text-sm font-semibold font-display tracking-tight">{{ column.name }}</h2>
      </div>
      <span
        v-if="total_count > 0"
        class="text-xs text-muted-foreground tabular-nums"
        :title="phase === 'brainstorm' ? 'Total cards (including others, hidden until reveal)' : 'Cards'"
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
        :is_mine="card.author_user_id === current_user_id"
        :tally="tallies[card.id] ?? card.vote_count"
        :is_my_vote="my_votes.has(card.id)"
        :votes_remaining="votes_remaining"
        :is_host="is_host"
        :is_discussing="card.id === discussing_card_id"
      />

      <!-- Face-down "card-back" placeholders for cards others
           have written but you can't see until :reveal. One per
           hidden card. Brand gradient matches the poker
           card-back silhouette (assets/vue/activities/poker/
           ParticipantsRow.vue) so the visual language for
           "hidden until reveal" is consistent across activities. -->
      <div
        v-for="n in hidden_count"
        :key="`hidden-${n}`"
        class="retro-card-back"
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
        <span class="text-[10px] text-muted-foreground tabular-nums">
          {{ draft.length }}/280
        </span>
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
/* Brand gradient back, matching poker's card-back (pink → cyan →
   green diagonal). Sized to match a real RetroCard's typical
   single-line content height so the layout barely shifts when
   placeholders flip to real content at :reveal. The diagonal
   angle is the same 135deg as the poker silhouette for visual
   continuity across activities. */
.retro-card-back {
  border-radius: 0.5rem;
  height: 4.5rem;
  background: linear-gradient(135deg, #e94886 0%, #56d2e6 50%, #b5e651 100%);
  border: 1px solid var(--primary);
  /* A subtle inset shadow keeps the gradient from reading as a
     flat sticker — feels like a physical card lying face-down. */
  box-shadow: inset 0 -1px 2px rgba(0, 0, 0, 0.15);
}
</style>
