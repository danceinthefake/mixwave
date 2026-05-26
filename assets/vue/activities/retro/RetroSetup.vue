<script setup lang="ts">
// Setup phase — host customises the session title + 4 column
// names. Locked once brainstorm begins (column rename is
// :setup-only, per spec §2).

import { ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import type { RetroSession } from "./RetroBoard.vue"

const props = defineProps<{
  session: RetroSession
  is_host: boolean
}>()

const live = useLiveVue()

// Local mirrors of the editable fields. Watch keeps them in sync
// when broadcasts update the session (e.g. another host edit).
const titleDraft = ref(props.session.title ?? "")
watch(
  () => props.session.title,
  (t) => {
    titleDraft.value = t ?? ""
  },
)

const columnDrafts = ref<Record<string, string>>(
  Object.fromEntries(props.session.columns.map((c) => [c.id, c.name])),
)
watch(
  () => props.session.columns.map((c) => [c.id, c.name]).join("|"),
  () => {
    columnDrafts.value = Object.fromEntries(props.session.columns.map((c) => [c.id, c.name]))
  },
)

function commitTitle() {
  const next = titleDraft.value.trim()
  if (next === (props.session.title ?? "").trim()) return
  live.pushEvent("retro_set_title", { title: next })
}

function commitColumn(columnId: string) {
  const next = (columnDrafts.value[columnId] ?? "").trim()
  if (!next) {
    // Restore the original — empty names are rejected server-side.
    const orig = props.session.columns.find((c) => c.id === columnId)
    columnDrafts.value[columnId] = orig?.name ?? ""
    return
  }
  const orig = props.session.columns.find((c) => c.id === columnId)
  if (orig?.name === next) return
  live.pushEvent("retro_rename_column", { column_id: columnId, name: next })
}

function toggleBrainstormVisible() {
  live.pushEvent("retro_set_brainstorm_visible", {
    visible: !props.session.brainstorm_visible,
  })
}
</script>

<template>
  <div class="space-y-6">
    <div v-if="!is_host" class="rounded-xl border bg-card p-6 text-sm text-muted-foreground italic">
      The host is setting up the retro — column names and the title. Hang tight; brainstorm will
      start soon.
    </div>

    <div v-if="is_host" class="space-y-4">
      <!-- Title -->
      <div class="space-y-1.5">
        <label
          for="retro-title"
          class="text-xs uppercase tracking-wider text-muted-foreground font-display"
        >
          Title <span class="normal-case text-muted-foreground/70">(optional)</span>
        </label>
        <input
          id="retro-title"
          v-model="titleDraft"
          @blur="commitTitle"
          @keydown.enter.prevent="commitTitle"
          type="text"
          maxlength="80"
          placeholder="e.g. Sprint 23 retro"
          class="w-full rounded-md border bg-card px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
        />
      </div>

      <!-- Column names -->
      <div class="space-y-1.5">
        <label class="text-xs uppercase tracking-wider text-muted-foreground font-display block">
          Column names
        </label>
        <p class="text-xs text-muted-foreground">
          Customise per your team's retro format. Locked once brainstorm starts.
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-2 pt-1">
          <div v-for="col in session.columns" :key="col.id" class="space-y-1">
            <input
              v-model="columnDrafts[col.id]"
              @blur="commitColumn(col.id)"
              @keydown.enter.prevent="commitColumn(col.id)"
              type="text"
              maxlength="40"
              :placeholder="`Column ${col.position + 1}`"
              :aria-label="`Rename column ${col.position + 1}`"
              class="w-full rounded-md border bg-card px-3 py-2 text-sm focus:outline-none focus:ring-2 focus:ring-accent-bass/40"
            />
          </div>
        </div>
      </div>

      <!-- Brainstorm visibility toggle -->
      <div class="space-y-1.5">
        <label class="inline-flex items-center gap-2 text-sm select-none cursor-pointer">
          <input
            type="checkbox"
            :checked="session.brainstorm_visible"
            @change="toggleBrainstormVisible"
            class="size-4 rounded border-input"
            aria-label="Show all cards during brainstorm (no hidden-until-reveal)"
          />
          Show all cards live during brainstorm
        </label>
        <p class="text-xs text-muted-foreground">
          Off (default): each person sees only their own cards until reveal — reduces groupthink,
          takes a beat longer. On: everyone sees everything as it's written — faster and more
          collaborative for smaller, high-trust teams. Locked once brainstorm starts.
        </p>
      </div>
    </div>
  </div>
</template>
