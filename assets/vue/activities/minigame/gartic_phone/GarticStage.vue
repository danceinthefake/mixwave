<script setup lang="ts">
// Gartic Phone stage (mini-game.md §9). Three phases:
//   :play   — everyone acts simultaneously on a private surface
//             (write a phrase / draw a prompt / describe a drawing),
//             then "waiting for everyone".
//   :album  — host steps the chain of each book through, page by page.
//   :gameover — browse every completed book.
//
// Reuses DrawingCanvas in `local` mode (private surface, submitted as a
// blob — no live relay). Text + drawing inputs push `minigame_submit`.

import { computed, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import type { GarticView, GarticEntry } from "../MiniGameBoard.vue"
import DrawingCanvas from "../pictionary/DrawingCanvas.vue"
import HowToPlay from "../HowToPlay.vue"

const props = defineProps<{
  state: GarticView
  current_user_id: string
  is_host: boolean
  nameOf: (id: string | null) => string
}>()

const live = useLiveVue()

const textDraft = ref("")
const canvasRef = ref<{ getStrokes: () => GarticEntry["strokes"] } | null>(null)

// Reset the text draft each new step.
watch(
  () => props.state.turn_token,
  () => {
    textDraft.value = ""
  },
)

// --- per-step countdown (display only, from the absolute deadline) ---
const now = ref(Date.now())
let ticker: number | undefined
watch(
  () => props.state.deadline,
  (deadline) => {
    // Guard SSR (no `window`); the immediate run happens during
    // server render too.
    if (typeof window === "undefined") return
    window.clearInterval(ticker)
    if (deadline) {
      now.value = Date.now()
      ticker = window.setInterval(() => (now.value = Date.now()), 250)
    }
  },
  { immediate: true },
)
onUnmounted(() => window.clearInterval(ticker))

const secondsLeft = computed(() => {
  if (!props.state.deadline) return null
  return Math.max(0, Math.ceil((props.state.deadline - now.value) / 1000))
})

const isWriting = computed(() => props.state.my_kind === "text")
const isDrawing = computed(() => props.state.my_kind === "drawing")

function submit() {
  if (isWriting.value) {
    const text = textDraft.value.trim()
    if (!text) return
    live.pushEvent("minigame_submit", { text })
  } else if (isDrawing.value) {
    const strokes = canvasRef.value?.getStrokes() ?? []
    live.pushEvent("minigame_submit", { strokes })
  }
}

// What the player is reacting to this step.
const promptText = computed(() =>
  props.state.prompt?.kind === "text" ? props.state.prompt.text : null,
)
const promptDrawing = computed(() =>
  props.state.prompt?.kind === "drawing" ? props.state.prompt : null,
)
</script>

<template>
  <!-- ===================== PLAY ===================== -->
  <div v-if="state.phase === 'play'" class="space-y-4">
    <div class="flex items-center justify-between gap-3 flex-wrap">
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        Step {{ (state.step ?? 0) + 1 }} / {{ state.total_steps }}
      </p>
      <div class="flex items-center gap-3">
        <span class="text-xs text-muted-foreground tabular-nums">
          {{ state.submitted_count }}/{{ state.player_count }} in
        </span>
        <span
          v-if="secondsLeft !== null"
          class="text-sm font-mono tabular-nums"
          :class="secondsLeft <= 10 ? 'text-destructive font-semibold' : 'text-muted-foreground'"
        >
          {{ secondsLeft }}s
        </span>
      </div>
    </div>

    <!-- Spectator (joined mid-game) -->
    <p
      v-if="state.is_player === false"
      class="text-sm text-muted-foreground italic text-center py-8"
    >
      Watching this round — you'll join the next game.
    </p>

    <!-- Already submitted → waiting -->
    <div v-else-if="state.submitted" class="rounded-xl border bg-card/60 p-6 text-center space-y-1">
      <p class="text-lg font-display font-semibold">Locked in ✓</p>
      <p class="text-sm text-muted-foreground">
        Waiting for everyone… {{ state.submitted_count }}/{{ state.player_count }}
      </p>
    </div>

    <!-- Active surface -->
    <div v-else class="space-y-3">
      <!-- The prompt to react to -->
      <div v-if="promptText" class="rounded-xl border bg-card/60 p-3">
        <p class="text-[11px] uppercase tracking-wider text-muted-foreground">Draw this</p>
        <p class="text-xl font-bold font-display">{{ promptText }}</p>
      </div>
      <div v-else-if="promptDrawing" class="space-y-1">
        <p class="text-[11px] uppercase tracking-wider text-muted-foreground">
          What's going on here?
        </p>
        <DrawingCanvas
          :strokes="promptDrawing.strokes"
          :is-drawer="false"
          :frozen="true"
          :local="true"
          :turn-token="state.turn_token ?? 0"
          :current_user_id="current_user_id"
        />
      </div>
      <p v-else class="text-sm text-muted-foreground">
        Kick off your book — write a word or phrase for the next player to draw.
      </p>

      <!-- The input -->
      <DrawingCanvas
        v-if="isDrawing"
        ref="canvasRef"
        :strokes="[]"
        :is-drawer="true"
        :frozen="false"
        :local="true"
        :turn-token="state.turn_token ?? 0"
        :current_user_id="current_user_id"
      />
      <input
        v-else
        v-model="textDraft"
        type="text"
        maxlength="200"
        :placeholder="promptDrawing ? 'Describe the drawing…' : 'Your phrase…'"
        autocomplete="off"
        @keydown.enter="submit"
        class="w-full bg-background border border-input rounded-md px-3 py-2 text-sm outline-none focus:border-accent-minigame/60"
      />

      <div class="flex justify-end">
        <button
          type="button"
          :disabled="isWriting && !textDraft.trim()"
          @click="submit"
          class="px-4 py-1.5 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 cursor-pointer font-medium disabled:opacity-50 disabled:cursor-not-allowed"
        >
          Submit
        </button>
      </div>
    </div>

    <!-- Host can force a stalled step forward -->
    <div v-if="is_host" class="flex justify-center pt-1">
      <button
        type="button"
        @click="live.pushEvent('minigame_skip', {})"
        class="px-3 py-1 text-xs rounded-md border bg-card hover:bg-accent text-muted-foreground cursor-pointer transition-colors"
      >
        Skip the wait →
      </button>
    </div>
  </div>

  <!-- ===================== ALBUM ===================== -->
  <div v-else-if="state.phase === 'album'" class="space-y-4">
    <div class="text-center space-y-1">
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        Album · book {{ (state.album_book ?? 0) + 1 }} / {{ state.total_books }}
      </p>
      <h3 class="text-xl font-bold font-display">{{ nameOf(state.book_owner ?? null) }}'s book</h3>
    </div>

    <ol class="space-y-3">
      <li
        v-for="(entry, i) in state.pages ?? []"
        :key="i"
        class="rounded-xl border bg-card/60 p-3 space-y-1"
      >
        <p class="text-[11px] uppercase tracking-wider text-muted-foreground">
          {{ i === 0 ? "Started by" : "then" }} {{ nameOf(entry.by) }}
        </p>
        <p v-if="entry.kind === 'text'" class="text-lg font-display">{{ entry.text }}</p>
        <DrawingCanvas
          v-else
          :strokes="entry.strokes"
          :is-drawer="false"
          :frozen="true"
          :local="true"
          :turn-token="i"
          :current_user_id="current_user_id"
        />
      </li>
    </ol>

    <div class="flex justify-center">
      <button
        v-if="is_host"
        type="button"
        @click="live.pushEvent('minigame_album_next', {})"
        class="px-4 py-1.5 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 cursor-pointer font-medium"
      >
        Next →
      </button>
      <p v-else class="text-sm text-muted-foreground italic">Host is presenting the album…</p>
    </div>
  </div>

  <!-- ===================== GAME OVER (browse all) ===================== -->
  <div v-else-if="state.phase === 'gameover'" class="space-y-4">
    <div class="text-center space-y-1">
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        That's a wrap
      </p>
      <h3 class="text-2xl font-bold font-display">All the books</h3>
    </div>
    <details
      v-for="(book, b) in state.books ?? []"
      :key="b"
      class="rounded-xl border bg-card/60 overflow-hidden"
      :open="b === 0"
    >
      <summary
        class="cursor-pointer px-4 py-2 text-sm font-semibold font-display hover:bg-accent/30"
      >
        {{ nameOf(book.owner) }}'s book
      </summary>
      <ol class="border-t px-4 py-3 space-y-3">
        <li v-for="(entry, i) in book.pages" :key="i" class="space-y-1">
          <p class="text-[11px] uppercase tracking-wider text-muted-foreground">
            {{ nameOf(entry.by) }}
          </p>
          <p v-if="entry.kind === 'text'" class="text-base font-display">{{ entry.text }}</p>
          <DrawingCanvas
            v-else
            :strokes="entry.strokes"
            :is-drawer="false"
            :frozen="true"
            :local="true"
            :turn-token="b * 100 + i"
            :current_user_id="current_user_id"
          />
        </li>
      </ol>
    </details>
    <p v-if="!is_host" class="text-center text-sm text-muted-foreground">
      Waiting for the host to play again or end.
    </p>
  </div>

  <!-- Rules reference, available to everyone while the game runs. -->
  <HowToPlay game="gartic_phone" />
</template>
