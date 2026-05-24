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
      return "Reveal cards"
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
