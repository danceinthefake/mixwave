<script setup lang="ts">
// Host-only controls: reveal / next-round + deck dropdown. The
// deck dropdown is disabled when `has_votes` is true — switching
// decks mid-vote would orphan whatever's already in the tally
// (see features/planning-poker.md §3). PokerBoard.vue v-if's this
// component on `is_host`.

import { computed, ref, watch } from "vue"
import type { DeckId, PokerStatus } from "./PokerBoard.vue"

const props = defineProps<{
  status: PokerStatus
  deck: DeckId
  queue: string[]
  has_votes: boolean
}>()

const emit = defineEmits<{
  reveal: []
  revote: []
  "next-round": []
  "change-deck": [deck: DeckId]
  "set-queue": [queue: string[]]
}>()

// Queue editor: a host-only textarea pre-filled with the current
// queue (one per line). Submit replaces the whole queue server-
// side. We keep the draft local while the disclosure is open so
// the host can edit without each keystroke racing the broadcast.
const draft = ref(props.queue.join("\n"))

// Whenever the queue updates from the server (the host saved, or
// `next_round` popped the head), re-sync the draft IF the editor
// is closed. Don't stomp on a half-edited paste.
const editorOpen = ref(false)
watch(
  () => props.queue,
  (q) => {
    if (!editorOpen.value) draft.value = q.join("\n")
  },
)

function saveQueue() {
  const lines = draft.value.split(/\r?\n/)
  emit("set-queue", lines)
  editorOpen.value = false
}

function clearQueue() {
  draft.value = ""
  emit("set-queue", [])
  editorOpen.value = false
}

const queueSummary = computed(() => {
  const n = props.queue.length
  if (n === 0) return "No backlog loaded"
  if (n === 1) return "1 story queued"
  return `${n} stories queued`
})

const deckLabels: Record<DeckId, string> = {
  fibonacci: "Fibonacci",
  modified_fibonacci: "Modified Fibonacci",
  tshirt: "T-shirt sizes",
  pow2: "Powers of 2",
}
</script>

<template>
  <div class="rounded-xl border bg-card/60 backdrop-blur-sm p-4 space-y-3">
    <div class="flex items-center justify-between gap-3">
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        Host controls
      </p>
      <div class="flex items-center gap-2">
        <button
          v-if="status === 'voting'"
          type="button"
          @click="$emit('reveal')"
          class="px-3 py-1.5 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 hover:-translate-y-px hover:shadow-md transition-all cursor-pointer font-medium inline-flex items-center gap-1.5"
          title="Flip everyone's cards. Keyboard: R"
        >
          Reveal
          <kbd
            aria-hidden="true"
            class="hidden sm:inline-block text-[10px] px-1 rounded bg-background/30 text-primary-foreground/80 font-mono font-normal"
          >
            R
          </kbd>
        </button>
        <template v-else>
          <button
            type="button"
            @click="$emit('revote')"
            class="px-3 py-1.5 text-sm rounded-md border bg-card hover:bg-accent text-foreground cursor-pointer font-medium transition-colors inline-flex items-center gap-1.5"
            title="Clear votes and let the team vote again on this same story. Keyboard: E"
          >
            Re-vote
            <kbd
              aria-hidden="true"
              class="hidden sm:inline-block text-[10px] px-1 rounded bg-muted text-muted-foreground font-mono font-normal"
            >
              E
            </kbd>
          </button>
          <button
            type="button"
            @click="$emit('next-round')"
            class="px-3 py-1.5 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 hover:-translate-y-px hover:shadow-md transition-all cursor-pointer font-medium inline-flex items-center gap-1.5"
            title="Move on to the next story (round number advances). Keyboard: N"
          >
            Next round
            <kbd
              aria-hidden="true"
              class="hidden sm:inline-block text-[10px] px-1 rounded bg-background/30 text-primary-foreground/80 font-mono font-normal"
            >
              N
            </kbd>
          </button>
        </template>
      </div>
    </div>

    <div class="flex items-center gap-2">
      <label for="poker-deck-select" class="text-xs text-muted-foreground">Deck</label>
      <select
        id="poker-deck-select"
        :value="deck"
        :disabled="has_votes"
        @change="(e) => $emit('change-deck', (e.target as HTMLSelectElement).value as DeckId)"
        class="px-2 py-1 text-xs rounded-md border bg-card text-foreground disabled:opacity-50 disabled:cursor-not-allowed cursor-pointer"
      >
        <option v-for="(label, id) in deckLabels" :key="id" :value="id">
          {{ label }}
        </option>
      </select>
      <span v-if="has_votes" class="text-[11px] text-muted-foreground italic">
        Lock the round before switching decks.
      </span>
    </div>

    <!-- Backlog editor. Native `<details>` so it's keyboard-
         accessible without our own state machine. Textarea is
         pre-filled with the current queue (one per line) so
         "append" is just type-more-then-save and "remove" is
         delete-a-line. Save replaces the whole queue server-
         side; PokerSession trims blanks and caps at 50 lines. -->
    <details
      class="rounded-md border border-dashed border-border/60 group"
      @toggle="(e) => (editorOpen = (e.target as HTMLDetailsElement).open)"
    >
      <summary
        class="cursor-pointer list-none px-3 py-2 flex items-center justify-between gap-3 hover:bg-accent/30 transition-colors rounded-md"
      >
        <span class="text-xs uppercase tracking-wider text-muted-foreground font-display">
          Story backlog
        </span>
        <span class="flex items-center gap-2 text-[11px] text-muted-foreground">
          <span class="italic">{{ queueSummary }}</span>
          <span aria-hidden="true" class="transition-transform group-open:rotate-180 select-none">▾</span>
        </span>
      </summary>
      <div class="border-t px-3 py-3 space-y-2">
        <label for="poker-queue-textarea" class="block text-[11px] text-muted-foreground">
          One story per line. Save replaces the queue; the next
          line drops in as the current story each time you click
          Next round.
        </label>
        <textarea
          id="poker-queue-textarea"
          v-model="draft"
          rows="6"
          placeholder="Add dark mode&#10;Migrate auth&#10;Fix dashboard loading state"
          class="w-full bg-background border border-input rounded-md px-2 py-1.5 text-sm font-mono outline-none focus:border-primary/60 resize-y"
        ></textarea>
        <div class="flex items-center justify-end gap-2">
          <button
            v-if="queue.length > 0"
            type="button"
            @click="clearQueue"
            class="px-3 py-1 text-xs rounded-md border bg-card hover:bg-accent text-muted-foreground cursor-pointer font-medium transition-colors"
            title="Empty the queue"
          >
            Clear
          </button>
          <button
            type="button"
            @click="saveQueue"
            class="px-3 py-1 text-xs rounded-md bg-primary text-primary-foreground hover:bg-primary/90 cursor-pointer font-medium transition-colors"
          >
            Save backlog
          </button>
        </div>
      </div>
    </details>
  </div>
</template>
