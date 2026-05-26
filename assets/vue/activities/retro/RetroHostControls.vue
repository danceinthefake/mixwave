<script setup lang="ts">
// Host-only controls: phase advance button + voting-enabled
// toggle (spec §5: visible :setup through :voting, hidden in
// :discuss / :archived). Sticks to the bottom of the board.

import { computed } from "vue"
import { useLiveVue } from "live_vue"
import type { RetroSession } from "./RetroBoard.vue"

const props = defineProps<{
  session: RetroSession
  is_host: boolean
}>()

const live = useLiveVue()

const phase = computed(() => props.session.status)

const advanceLabel = computed(() => {
  switch (phase.value) {
    case "setup":
      return "Start brainstorm"
    case "brainstorm":
      // In always-visible mode, "Reveal cards" makes no sense
      // (nothing is hidden). The phase boundary still matters
      // as a "stop adding, start reading" gate — relabel
      // accordingly.
      return props.session.brainstorm_visible ? "Stop brainstorming" : "Reveal cards"
    case "reveal":
      return props.session.voting_enabled ? "Start voting" : "Start discussion"
    case "voting":
      return "Start discussion"
    case "discuss":
      return "Archive retro"
    case "archived":
      return null
    default:
      return null
  }
})

const advanceConfirm = computed(() => {
  // Archive is destructive — ask first. The wording firms up when
  // there's nothing to archive, per spec §9's empty-session
  // nudge: "No cards captured — are you sure?"
  if (phase.value !== "discuss") return null
  if (props.session.cards.length === 0) {
    return "No cards captured in this retro. Archive an empty session anyway?"
  }
  return "Archive this retro? No more edits after."
})

const showVotingToggle = computed(() =>
  ["setup", "brainstorm", "reveal", "voting"].includes(phase.value),
)

// Voting earns its keep when you have too many cards to discuss
// linearly in the time you've got. Empirically: ~15 cards is
// where a 25-min discussion window starts running out at 1
// minute per card. Below that, host can hand-pick what to talk
// about; above, dot-voting helps the team surface what actually
// matters. Hint shows only when voting is OFF (no point
// suggesting if already on) and during the toggle window.
const CARD_THRESHOLD = 15

const showVotingHint = computed(
  () =>
    showVotingToggle.value &&
    !props.session.voting_enabled &&
    props.session.cards.length >= CARD_THRESHOLD,
)

function advance() {
  if (advanceConfirm.value && !confirm(advanceConfirm.value)) return
  live.pushEvent("retro_advance_phase", {})
}

function toggleVoting() {
  live.pushEvent("retro_set_voting_enabled", { enabled: !props.session.voting_enabled })
}
</script>

<template>
  <footer
    v-if="is_host"
    class="sticky bottom-2 z-10 flex flex-wrap items-center justify-end gap-3 rounded-xl border bg-card/95 backdrop-blur px-4 py-2.5"
    role="toolbar"
    aria-label="Retro host controls"
  >
    <p v-if="showVotingHint" class="text-[11px] text-muted-foreground italic mr-auto" role="status">
      {{ session.cards.length }} cards — voting helps the team pick what's worth discussing.
    </p>

    <label
      v-if="showVotingToggle"
      class="inline-flex items-center gap-2 text-xs font-medium select-none cursor-pointer"
    >
      <input
        type="checkbox"
        :checked="session.voting_enabled"
        @change="toggleVoting"
        class="size-3.5 rounded border-input"
      />
      Enable voting
    </label>

    <button
      v-if="advanceLabel"
      type="button"
      @click="advance"
      class="rounded-md bg-accent-bass text-background px-4 py-1.5 text-sm font-medium hover:bg-accent-bass/90"
    >
      {{ advanceLabel }}
    </button>
  </footer>
</template>
