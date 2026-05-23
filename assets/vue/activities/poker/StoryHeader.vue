<script setup lang="ts">
// Story title at the top of the poker board. Host gets an inline
// editable input; everyone else sees a static heading. Falls back
// to "Round N" when story is nil so the round number stays visible.

import { ref, watch } from "vue"

const props = defineProps<{
  story: string | null
  round: number
  is_host: boolean
}>()

const emit = defineEmits<{ "update:story": [story: string] }>()

const draft = ref(props.story ?? "")
const editing = ref(false)

// Keep `draft` in sync if the LiveView pushes a fresh story (e.g.,
// another host edit in a multi-host future, or a `:cleared`
// broadcast that swapped the title on next-round). Don't stomp
// the user mid-edit.
watch(
  () => props.story,
  (newStory) => {
    if (!editing.value) draft.value = newStory ?? ""
  },
)

function startEdit() {
  if (!props.is_host) return
  draft.value = props.story ?? ""
  editing.value = true
}

function commit() {
  editing.value = false
  const next = draft.value.trim()
  if (next !== (props.story ?? "")) {
    emit("update:story", next)
  }
}

function cancel() {
  editing.value = false
  draft.value = props.story ?? ""
}
</script>

<template>
  <div class="space-y-1 text-center">
    <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
      Round {{ round }}
    </p>
    <template v-if="editing">
      <input
        v-model="draft"
        @blur="commit"
        @keydown.enter.prevent="commit"
        @keydown.escape.prevent="cancel"
        autofocus
        placeholder="What are we estimating?"
        class="w-full text-2xl font-bold tracking-tight font-display bg-transparent border-b border-input focus:border-primary outline-none py-1 text-center"
      />
    </template>
    <template v-else>
      <h2
        @click="startEdit"
        :class="[
          'text-2xl font-bold tracking-tight font-display',
          is_host && 'cursor-text hover:bg-accent/50 rounded -mx-1 px-1 transition-colors inline-block',
          !story && 'text-muted-foreground',
        ]"
        :title="is_host ? 'Click to edit' : undefined"
      >
        {{ story || "Click to set a story…" }}
      </h2>
    </template>
  </div>
</template>
