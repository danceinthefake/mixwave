<script setup lang="ts">
// One card. Phase-aware: brainstorm shows owner edit/delete on
// own cards; voting shows vote/unvote button + live tally;
// discuss + archived show static count + (host-only) discussing
// focus toggle.

import { computed, ref } from "vue"
import { useLiveVue } from "live_vue"
import type { RetroCard as RetroCardT, RetroPhase } from "./RetroBoard.vue"

const props = defineProps<{
  card: RetroCardT
  phase: RetroPhase
  is_mine: boolean
  tally: number
  is_my_vote: boolean
  votes_remaining: number
  is_host: boolean
  // Visually highlight this card if it's the currently-focused
  // discussion card (host-driven, broadcast to everyone).
  is_discussing: boolean
}>()

const live = useLiveVue()

const editing = ref(false)
const editDraft = ref(props.card.body)

const canVote = computed(() => props.is_my_vote || props.votes_remaining > 0)
const showVoteButton = computed(() => props.phase === "voting")
const showCount = computed(
  () => props.phase === "voting" || props.phase === "discuss" || props.phase === "archived",
)
const showEditDeleteAffordances = computed(() => props.phase === "brainstorm" && props.is_mine)

function startEdit() {
  editDraft.value = props.card.body
  editing.value = true
}

function commitEdit() {
  const body = editDraft.value.trim()
  if (!body) {
    editing.value = false
    return
  }
  if (body !== props.card.body) {
    live.pushEvent("retro_update_card", { card_id: props.card.id, body })
  }
  editing.value = false
}

function cancelEdit() {
  editDraft.value = props.card.body
  editing.value = false
}

function deleteCard() {
  if (!confirm("Delete this card?")) return
  live.pushEvent("retro_delete_card", { card_id: props.card.id })
}

function toggleVote() {
  if (props.is_my_vote) {
    live.pushEvent("retro_withdraw_vote", { card_id: props.card.id })
  } else if (props.votes_remaining > 0) {
    live.pushEvent("retro_vote", { card_id: props.card.id })
  }
}

function focusForDiscussion() {
  if (!props.is_host) return
  live.pushEvent("retro_set_discussing", { card_id: props.card.id })
}
</script>

<template>
  <article
    class="rounded-lg border bg-card p-2.5 space-y-2 group transition-all"
    :class="{
      'border-accent-bass/40': is_mine && phase === 'brainstorm',
      'cursor-pointer hover:border-accent-bass/40': is_host && phase === 'discuss',
      'ring-2 ring-accent-bass ring-offset-1 ring-offset-background border-accent-bass':
        is_discussing,
    }"
    @click="phase === 'discuss' ? focusForDiscussion() : undefined"
  >
    <div v-if="!editing" class="text-sm leading-snug whitespace-pre-wrap break-words">
      {{ card.body }}
    </div>

    <textarea
      v-else
      v-model="editDraft"
      maxlength="280"
      rows="3"
      class="w-full rounded-md border bg-background px-2 py-1.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
      @keydown.enter.exact.prevent="commitEdit"
      @keydown.escape="cancelEdit"
    ></textarea>

    <div class="flex items-center justify-between gap-2 text-[10px] text-muted-foreground">
      <span class="truncate">{{ card.author_alias }}</span>

      <div class="flex items-center gap-1.5">
        <!-- Edit/delete (brainstorm + own card) -->
        <template v-if="showEditDeleteAffordances && !editing">
          <button
            type="button"
            class="opacity-0 group-hover:opacity-100 transition-opacity hover:text-foreground"
            aria-label="Edit card"
            @click.stop="startEdit"
          >
            edit
          </button>
          <button
            type="button"
            class="opacity-0 group-hover:opacity-100 transition-opacity hover:text-destructive"
            aria-label="Delete card"
            @click.stop="deleteCard"
          >
            delete
          </button>
        </template>

        <template v-if="editing">
          <button
            type="button"
            class="hover:text-foreground"
            @click.stop="commitEdit"
          >
            save
          </button>
          <button
            type="button"
            class="hover:text-foreground"
            @click.stop="cancelEdit"
          >
            cancel
          </button>
        </template>

        <!-- Vote button -->
        <button
          v-if="showVoteButton"
          type="button"
          :disabled="!canVote"
          :aria-pressed="is_my_vote"
          :aria-label="is_my_vote ? 'Withdraw vote' : 'Vote for this card'"
          class="inline-flex items-center gap-1 rounded-md border px-1.5 py-0.5 text-[10px] font-medium transition-colors"
          :class="
            is_my_vote
              ? 'bg-accent-bass text-background border-accent-bass'
              : canVote
                ? 'hover:bg-accent border-input text-foreground'
                : 'opacity-40 cursor-not-allowed border-input'
          "
          @click.stop="toggleVote"
        >
          <span aria-hidden="true">●</span>
          <span class="tabular-nums">{{ tally }}</span>
        </button>

        <!-- Static count chip (discuss / archived) -->
        <span
          v-else-if="showCount && tally > 0"
          class="inline-flex items-center gap-1 rounded-md border border-input bg-card px-1.5 py-0.5 text-[10px] tabular-nums"
        >
          <span aria-hidden="true">●</span>
          {{ tally }}
        </span>
      </div>
    </div>
  </article>
</template>
