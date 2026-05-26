<script setup lang="ts">
// Flat comments thread on a retro card. Collapsed by default;
// click "N comments" to expand. Inline add form at the bottom
// when expanded. Each comment renders the alias · display_name
// two-piece author label (consistent with cards). Author can
// edit + delete during live phases (reveal/voting/discuss);
// everything is read-only on :archived.

import { computed, ref } from "vue"
import { useLiveVue } from "live_vue"
import type { RetroComment } from "./RetroBoard.vue"

const props = defineProps<{
  card_id: string
  comments: RetroComment[]
  current_user_id: string
  read_only: boolean
}>()

const live = useLiveVue()

const expanded = ref(false)
const draft = ref("")

// Trim long threads to keep the column compact. Once the user
// clicks "Load more" the rest unfolds and stays unfolded for
// the remainder of the session.
const TRIM_THRESHOLD = 3
const showAllComments = ref(false)
const visibleComments = computed<RetroComment[]>(() => {
  if (showAllComments.value || props.comments.length <= TRIM_THRESHOLD) {
    return props.comments
  }
  // Show the most recent 3 by default — preserves thread tail,
  // hides the older context behind the click.
  return props.comments.slice(-TRIM_THRESHOLD)
})
const hiddenCommentCount = computed(() =>
  Math.max(0, props.comments.length - visibleComments.value.length),
)

const editingId = ref<string | null>(null)
const editDraft = ref("")

function toggleExpanded() {
  expanded.value = !expanded.value
}

function submitComment() {
  const body = draft.value.trim()
  if (!body) return
  live.pushEvent("retro_add_comment", { card_id: props.card_id, body })
  draft.value = ""
}

function startEdit(comment: RetroComment) {
  editingId.value = comment.id
  editDraft.value = comment.body
}

function commitEdit() {
  if (!editingId.value) return
  const body = editDraft.value.trim()
  if (!body) {
    cancelEdit()
    return
  }
  live.pushEvent("retro_update_comment", { comment_id: editingId.value, body })
  editingId.value = null
}

function cancelEdit() {
  editingId.value = null
}

function deleteComment(comment: RetroComment) {
  if (!confirm("Delete this comment?")) return
  live.pushEvent("retro_delete_comment", { comment_id: comment.id })
}
</script>

<template>
  <div class="pt-2 mt-2 border-t border-input/40">
    <button
      type="button"
      class="text-[10px] text-muted-foreground hover:text-foreground inline-flex items-center gap-1"
      :aria-expanded="expanded"
      :aria-controls="`comments-${card_id}`"
      @click.stop="toggleExpanded"
    >
      <span aria-hidden="true">💬</span>
      <span>{{ comments.length }} {{ comments.length === 1 ? "comment" : "comments" }}</span>
      <span class="transition-transform" :class="expanded && 'rotate-90'" aria-hidden="true"
        >›</span
      >
    </button>

    <div v-if="expanded" :id="`comments-${card_id}`" class="mt-2 space-y-2" @click.stop>
      <p v-if="comments.length === 0" class="text-[11px] text-muted-foreground italic">
        No comments yet.
      </p>

      <button
        v-if="hiddenCommentCount > 0"
        type="button"
        class="w-full text-[11px] text-muted-foreground hover:text-foreground italic text-left"
        @click="showAllComments = true"
      >
        Load {{ hiddenCommentCount }} earlier
        {{ hiddenCommentCount === 1 ? "comment" : "comments" }}
      </button>

      <div
        v-for="comment in visibleComments"
        :key="comment.id"
        class="rounded-md border bg-background/40 p-2 text-xs space-y-1 group"
      >
        <div v-if="editingId !== comment.id" class="space-y-1">
          <p class="leading-snug break-words">{{ comment.body }}</p>
          <div class="flex items-center justify-between gap-2 text-[10px] text-muted-foreground">
            <span class="truncate">
              {{ comment.author_alias
              }}<span
                v-if="
                  comment.author_display_name &&
                  comment.author_display_name !== comment.author_alias
                "
                class="text-muted-foreground/70"
              >
                · {{ comment.author_display_name }}</span
              >
            </span>
            <div
              v-if="!read_only && comment.author_user_id === current_user_id"
              class="flex items-center gap-1.5 opacity-0 group-hover:opacity-100 transition-opacity"
            >
              <button type="button" class="hover:text-foreground" @click="startEdit(comment)">
                edit
              </button>
              <button type="button" class="hover:text-destructive" @click="deleteComment(comment)">
                delete
              </button>
            </div>
          </div>
        </div>

        <div v-else class="space-y-1.5">
          <textarea
            v-model="editDraft"
            maxlength="280"
            rows="2"
            aria-label="Edit comment"
            class="w-full rounded-md border bg-card px-2 py-1 text-xs resize-none focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
            @keydown.enter.exact.prevent="commitEdit"
            @keydown.escape="cancelEdit"
          ></textarea>
          <div class="flex justify-end gap-2 text-[10px]">
            <button
              type="button"
              class="text-muted-foreground hover:text-foreground"
              @click="cancelEdit"
            >
              cancel
            </button>
            <button
              type="button"
              class="font-medium rounded-md bg-accent-bass text-background px-2 py-0.5 hover:bg-accent-bass/90"
              @click="commitEdit"
            >
              save
            </button>
          </div>
        </div>
      </div>

      <form v-if="!read_only" @submit.prevent="submitComment" class="space-y-1.5 pt-1">
        <textarea
          v-model="draft"
          maxlength="280"
          rows="2"
          placeholder="Add a comment…"
          :aria-label="`Add comment to this card`"
          class="w-full rounded-md border bg-card px-2 py-1 text-xs resize-none focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
          @keydown.enter.exact.prevent="submitComment"
        ></textarea>
        <div class="flex justify-end">
          <button
            type="submit"
            :disabled="!draft.trim()"
            class="text-[10px] font-medium rounded-md bg-accent-bass text-background px-2 py-0.5 hover:bg-accent-bass/90 disabled:opacity-40 disabled:cursor-not-allowed"
          >
            Add
          </button>
        </div>
      </form>
    </div>
  </div>
</template>
