<script setup lang="ts">
// One action item row — display + inline edit mode. Used in two
// places: nested under its source card in RetroCard (during
// :discuss/:archived), and in RetroDiscussPanel for freeform
// actions. Centralising the row UI keeps the edit/toggle/delete
// affordances consistent across both contexts.

import { computed, inject, ref, type ComputedRef } from "vue"
import { useLiveVue } from "live_vue"
import type { RetroActionItem } from "./RetroBoard.vue"

// Provided by RetroBoard so the assignee input can autocomplete
// from current chamber presence without prop-drilling through
// RetroColumn + RetroCard. Falls back to [] when the provider
// isn't present (tests / standalone renders).
const participantAliases = inject<ComputedRef<string[]>>(
  "retro_participant_aliases",
  computed(() => []),
)

// Stable id per mounted row so multiple datalists don't collide
// when more than one row is in edit mode.
const datalistId = `retro-assignees-${Math.random().toString(36).slice(2, 10)}`

const props = defineProps<{
  action: RetroActionItem
  read_only: boolean
  // When true, hide the "re: <card body>" tail — the row is
  // already nested under the source card so the context is
  // implicit. RetroDiscussPanel's freeform list never has a
  // source card to reference.
  hide_source_ref?: boolean
  source_card_body?: string | null
}>()

const live = useLiveVue()

const editing = ref(false)
const editDraft = ref({
  body: props.action.body,
  assignee_alias: props.action.assignee_alias ?? "",
  due_date: props.action.due_date ?? "",
})

function startEdit() {
  if (props.read_only) return
  editDraft.value = {
    body: props.action.body,
    assignee_alias: props.action.assignee_alias ?? "",
    due_date: props.action.due_date ?? "",
  }
  editing.value = true
}

function commitEdit() {
  const body = editDraft.value.body.trim()
  if (!body) {
    cancelEdit()
    return
  }
  const payload: Record<string, unknown> = { action_id: props.action.id }
  if (body !== props.action.body) payload.body = body
  if (editDraft.value.assignee_alias.trim() !== (props.action.assignee_alias ?? "")) {
    payload.assignee_alias = editDraft.value.assignee_alias.trim() || null
  }
  if (editDraft.value.due_date !== (props.action.due_date ?? "")) {
    payload.due_date = editDraft.value.due_date || null
  }
  if (Object.keys(payload).length > 1) {
    live.pushEvent("retro_update_action_item", payload)
  }
  editing.value = false
}

function cancelEdit() {
  editing.value = false
}

function toggleCompleted() {
  if (props.read_only) return
  live.pushEvent("retro_update_action_item", {
    action_id: props.action.id,
    completed: !props.action.completed,
  })
}

function deleteRow() {
  if (props.read_only) return
  if (!confirm("Delete this action item?")) return
  live.pushEvent("retro_delete_action_item", { action_id: props.action.id })
}
</script>

<template>
  <div class="rounded-lg border bg-background/40 p-2.5 flex items-start gap-2">
    <input
      type="checkbox"
      :checked="action.completed"
      :disabled="read_only || editing"
      :aria-label="`Mark ${action.body} as ${action.completed ? 'incomplete' : 'complete'}`"
      @change="toggleCompleted"
      class="mt-0.5 size-4 rounded border-input"
    />

    <!-- Display -->
    <div v-if="!editing" class="flex-1 min-w-0 space-y-0.5">
      <p
        class="text-sm leading-snug break-words"
        :class="action.completed && 'line-through text-muted-foreground'"
      >
        {{ action.body }}
      </p>
      <div class="flex items-center gap-2 text-[11px] text-muted-foreground flex-wrap">
        <span v-if="action.assignee_alias" class="font-medium"> @{{ action.assignee_alias }} </span>
        <span v-if="action.due_date">due {{ action.due_date }}</span>
        <span v-if="!hide_source_ref && source_card_body" class="italic truncate max-w-xs">
          re: {{ source_card_body }}
        </span>
      </div>
    </div>

    <!-- Edit -->
    <div v-else class="flex-1 min-w-0 space-y-2">
      <textarea
        v-model="editDraft.body"
        maxlength="280"
        rows="2"
        :aria-label="`Edit action body`"
        class="w-full rounded-md border bg-card px-2 py-1.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        @keydown.enter.exact.prevent="commitEdit"
        @keydown.escape="cancelEdit"
      ></textarea>
      <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
        <input
          v-model="editDraft.assignee_alias"
          type="text"
          maxlength="80"
          placeholder="Assignee (optional)"
          aria-label="Edit assignee alias"
          :list="datalistId"
          class="rounded-md border bg-card px-2 py-1 text-xs focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        />
        <datalist :id="datalistId">
          <option v-for="name in participantAliases" :key="name" :value="name" />
        </datalist>
        <input
          v-model="editDraft.due_date"
          type="date"
          aria-label="Edit due date"
          class="rounded-md border bg-card px-2 py-1 text-xs focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        />
      </div>
      <div class="flex justify-end gap-2 text-[11px]">
        <button
          type="button"
          class="hover:text-foreground text-muted-foreground"
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

    <!-- Edit / delete -->
    <div v-if="!read_only && !editing" class="flex items-center gap-1.5">
      <button
        type="button"
        class="text-[11px] text-muted-foreground hover:text-foreground"
        @click="startEdit"
        :aria-label="`Edit action: ${action.body}`"
      >
        edit
      </button>
      <button
        type="button"
        class="text-[11px] text-muted-foreground hover:text-destructive"
        @click="deleteRow"
        :aria-label="`Delete action: ${action.body}`"
      >
        ×
      </button>
    </div>
  </div>
</template>
