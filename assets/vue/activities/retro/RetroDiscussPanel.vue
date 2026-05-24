<script setup lang="ts">
// Action items panel — visible during :discuss and read-only
// during :archived. Anyone in the chamber can add actions
// during :discuss; only the host has phase-advance / archive
// authority. Actions can be tied to a source card (spec §6)
// or freeform.

import { computed, ref } from "vue"
import { useLiveVue } from "live_vue"
import type { RetroSession, RetroCard, RetroActionItem } from "./RetroBoard.vue"

const props = defineProps<{
  session: RetroSession
  is_host: boolean
}>()

const live = useLiveVue()

const readOnly = computed(() => props.session.status === "archived")

const draft = ref({
  body: "",
  source_card_id: "",
  assignee_alias: "",
  due_date: "",
})

// Action being inline-edited (id or null). Local draft holds
// the in-flight values; committing pushes a single
// retro_update_action_item event for whichever fields changed.
const editingId = ref<string | null>(null)
const editDraft = ref({
  body: "",
  assignee_alias: "",
  due_date: "",
})

const cardsById = computed(() => {
  const map: Record<string, RetroCard> = {}
  for (const c of props.session.cards) map[c.id] = c
  return map
})

function startEdit(action: RetroActionItem) {
  if (readOnly.value) return
  editingId.value = action.id
  editDraft.value = {
    body: action.body,
    assignee_alias: action.assignee_alias ?? "",
    due_date: action.due_date ?? "",
  }
}

function commitEdit(action: RetroActionItem) {
  const body = editDraft.value.body.trim()
  if (!body) {
    cancelEdit()
    return
  }
  const payload: Record<string, unknown> = { action_id: action.id }
  if (body !== action.body) payload.body = body
  if (editDraft.value.assignee_alias.trim() !== (action.assignee_alias ?? "")) {
    payload.assignee_alias = editDraft.value.assignee_alias.trim() || null
  }
  if (editDraft.value.due_date !== (action.due_date ?? "")) {
    payload.due_date = editDraft.value.due_date || null
  }
  // No fields changed — just close edit mode without pushing.
  if (Object.keys(payload).length > 1) {
    live.pushEvent("retro_update_action_item", payload)
  }
  editingId.value = null
}

function cancelEdit() {
  editingId.value = null
}

function submit() {
  const body = draft.value.body.trim()
  if (!body) return
  live.pushEvent("retro_add_action_item", {
    body,
    source_card_id: draft.value.source_card_id || null,
    assignee_alias: draft.value.assignee_alias.trim() || null,
    due_date: draft.value.due_date || null,
  })
  draft.value.body = ""
  draft.value.source_card_id = ""
  draft.value.assignee_alias = ""
  draft.value.due_date = ""
}

function toggleCompleted(action: RetroActionItem) {
  if (readOnly.value) return
  live.pushEvent("retro_update_action_item", {
    action_id: action.id,
    completed: !action.completed,
  })
}

function deleteAction(action: RetroActionItem) {
  if (readOnly.value) return
  if (!confirm("Delete this action item?")) return
  live.pushEvent("retro_delete_action_item", { action_id: action.id })
}

function exportMarkdown() {
  const lines: string[] = []
  lines.push(`# ${props.session.title || "Retro"}`)
  lines.push("")
  for (const col of props.session.columns) {
    lines.push(`## ${col.name}`)
    const colCards = props.session.cards
      .filter((c) => c.retro_column_id === col.id)
      .sort((a, b) => b.vote_count - a.vote_count)
    if (colCards.length === 0) {
      lines.push("  _(no cards)_")
    } else {
      for (const c of colCards) {
        const votes = c.vote_count > 0 ? ` _(${c.vote_count} votes)_` : ""
        lines.push(`- ${c.body}${votes} — ${c.author_alias}`)
      }
    }
    lines.push("")
  }
  if (props.session.action_items.length > 0) {
    lines.push(`## Action items`)
    for (const a of props.session.action_items) {
      const tied = a.source_card_id ? ` _(re: ${cardsById.value[a.source_card_id]?.body ?? "?"})_` : ""
      const assignee = a.assignee_alias ? ` — @${a.assignee_alias}` : ""
      const due = a.due_date ? ` _(by ${a.due_date})_` : ""
      const done = a.completed ? "[x] " : "[ ] "
      lines.push(`- ${done}${a.body}${assignee}${due}${tied}`)
    }
  }
  const text = lines.join("\n")

  navigator.clipboard?.writeText(text).then(
    () => alert("Markdown copied to clipboard."),
    () => alert("Couldn't copy. Manually copy from the console.\n\n" + text),
  )
}
</script>

<template>
  <section class="rounded-xl border bg-card/40 p-4 space-y-4">
    <header class="flex items-baseline justify-between gap-3">
      <h2 class="text-sm uppercase tracking-wider text-muted-foreground font-display">
        Action items
      </h2>
      <button
        v-if="readOnly"
        type="button"
        @click="exportMarkdown"
        class="text-xs font-medium rounded-md border px-3 py-1 hover:bg-accent"
      >
        Copy as markdown
      </button>
    </header>

    <ul v-if="session.action_items.length > 0" class="space-y-2">
      <li
        v-for="action in session.action_items"
        :key="action.id"
        class="rounded-lg border bg-background/40 p-3 flex items-start gap-3"
      >
        <input
          type="checkbox"
          :checked="action.completed"
          :disabled="readOnly || editingId === action.id"
          :aria-label="`Mark ${action.body} as ${action.completed ? 'incomplete' : 'complete'}`"
          @change="toggleCompleted(action)"
          class="mt-0.5 size-4 rounded border-input"
        />

        <!-- Display mode -->
        <div v-if="editingId !== action.id" class="flex-1 space-y-1">
          <p
            class="text-sm leading-snug"
            :class="action.completed && 'line-through text-muted-foreground'"
          >
            {{ action.body }}
          </p>
          <div class="flex items-center gap-2 text-[11px] text-muted-foreground flex-wrap">
            <span v-if="action.assignee_alias" class="font-medium">
              @{{ action.assignee_alias }}
            </span>
            <span v-if="action.due_date">due {{ action.due_date }}</span>
            <span
              v-if="action.source_card_id && cardsById[action.source_card_id]"
              class="italic truncate max-w-xs"
            >
              re: {{ cardsById[action.source_card_id].body }}
            </span>
          </div>
        </div>

        <!-- Edit mode -->
        <div v-else class="flex-1 space-y-2">
          <textarea
            v-model="editDraft.body"
            maxlength="280"
            rows="2"
            :aria-label="`Edit action body`"
            class="w-full rounded-md border bg-card px-2 py-1.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
            @keydown.enter.exact.prevent="commitEdit(action)"
            @keydown.escape="cancelEdit"
          ></textarea>
          <div class="grid grid-cols-1 sm:grid-cols-2 gap-2">
            <input
              v-model="editDraft.assignee_alias"
              type="text"
              maxlength="80"
              placeholder="Assignee (optional)"
              aria-label="Edit assignee alias"
              class="rounded-md border bg-card px-2 py-1 text-xs focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
            />
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
              @click="commitEdit(action)"
            >
              save
            </button>
          </div>
        </div>

        <!-- Edit + delete affordances -->
        <div
          v-if="!readOnly && editingId !== action.id"
          class="flex items-center gap-1.5"
        >
          <button
            type="button"
            class="text-[11px] text-muted-foreground hover:text-foreground"
            @click="startEdit(action)"
            :aria-label="`Edit action: ${action.body}`"
          >
            edit
          </button>
          <button
            type="button"
            class="text-[11px] text-muted-foreground hover:text-destructive"
            @click="deleteAction(action)"
            :aria-label="`Delete action: ${action.body}`"
          >
            ×
          </button>
        </div>
      </li>
    </ul>

    <p v-else class="text-xs text-muted-foreground italic">
      No action items captured yet.
    </p>

    <!-- Add form — discuss only -->
    <form v-if="!readOnly" @submit.prevent="submit" class="space-y-2 pt-2 border-t">
      <textarea
        v-model="draft.body"
        maxlength="280"
        rows="2"
        placeholder="Add an action item…"
        aria-label="New action item body"
        class="w-full rounded-md border bg-card px-2.5 py-1.5 text-sm resize-none focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
      ></textarea>
      <div class="grid grid-cols-1 sm:grid-cols-3 gap-2">
        <input
          v-model="draft.assignee_alias"
          type="text"
          maxlength="80"
          placeholder="Assignee (optional)"
          aria-label="Assignee alias"
          class="rounded-md border bg-card px-2.5 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        />
        <input
          v-model="draft.due_date"
          type="date"
          aria-label="Due date"
          class="rounded-md border bg-card px-2.5 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        />
        <select
          v-model="draft.source_card_id"
          aria-label="Tie to a card (optional)"
          class="rounded-md border bg-card px-2.5 py-1.5 text-xs focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        >
          <option value="">No source card</option>
          <option v-for="c in session.cards" :key="c.id" :value="c.id">
            {{ c.body.slice(0, 50) }}{{ c.body.length > 50 ? "…" : "" }}
          </option>
        </select>
      </div>
      <div class="flex justify-end">
        <button
          type="submit"
          :disabled="!draft.body.trim()"
          class="text-xs font-medium rounded-md bg-accent-bass text-background px-3 py-1.5 hover:bg-accent-bass/90 disabled:opacity-40 disabled:cursor-not-allowed"
        >
          Add action
        </button>
      </div>
    </form>
  </section>
</template>
