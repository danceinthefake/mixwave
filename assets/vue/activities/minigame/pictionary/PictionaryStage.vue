<script setup lang="ts">
// Orchestrates a Pictionary :turn / :turn_reveal (features/mini-game.md
// §2): the word/blanks banner + timer up top, the shared canvas in the
// middle, the guess feed below. Word-choice picker shows for the drawer
// while choosing; the secret word only ever renders for the drawer (or
// for everyone at reveal — the server already gates `state.word`).

import { computed, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import { playGuessCorrect, playTimeUp } from "../../../lib/audio"
import type { MiniGameView } from "../MiniGameBoard.vue"
import DrawingCanvas from "./DrawingCanvas.vue"
import GuessFeed from "./GuessFeed.vue"
import HowToPlay from "../HowToPlay.vue"

const props = defineProps<{
  state: MiniGameView
  current_user_id: string
  drawerName: string
  nameOf: (id: string | null) => string
}>()

const live = useLiveVue()

const isReveal = computed(() => props.state.phase === "turn_reveal")

// --- Timer: drive a display-only countdown from the absolute
// server `deadline` so every client agrees on time-left regardless
// of latency (spec "Notes"). ---
const now = ref(Date.now())
let ticker: number | undefined
watch(
  () => props.state.deadline,
  (deadline) => {
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

// Time-up buzzer: fire once when the clock reaches 0 while the turn is
// still live (an early all-guessed/skip end flips the phase first, so
// this only catches genuine timeouts).
watch(secondsLeft, (now, prev) => {
  if (now === 0 && prev !== null && prev > 0 && props.state.phase === "turn") {
    void playTimeUp()
  }
})

// Correct-guess blip — the whole room hears it (the drawer doesn't
// mount GuessFeed, so the cue lives here, on the always-mounted stage).
live.handleEvent("minigame_feed", (payload: { type: string }) => {
  if (payload.type === "correct") void playGuessCorrect()
})
const timerPct = computed(() => {
  if (secondsLeft.value === null) return 0
  return Math.min(100, (secondsLeft.value / props.state.config.turn_seconds) * 100)
})

function chooseWord(word: string) {
  live.pushEvent("minigame_choose_word", { word })
}
</script>

<template>
  <div class="space-y-3">
    <!-- Banner: word / blanks / choosing / reveal -->
    <div class="rounded-xl border bg-card/60 p-3 space-y-2">
      <div class="flex items-center justify-between gap-3">
        <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
          <template v-if="isReveal">Round result</template>
          <template v-else-if="state.is_drawer">You're drawing</template>
          <template v-else>{{ drawerName }} is drawing</template>
        </p>
        <div
          v-if="secondsLeft !== null"
          class="text-sm font-mono tabular-nums"
          :class="secondsLeft <= 10 ? 'text-destructive font-semibold' : 'text-muted-foreground'"
        >
          {{ secondsLeft }}s
        </div>
      </div>

      <!-- Timer bar -->
      <div v-if="secondsLeft !== null" class="h-1 rounded-full bg-muted overflow-hidden">
        <div
          class="h-full bg-accent-minigame transition-[width] duration-200 ease-linear"
          :style="{ width: timerPct + '%' }"
        ></div>
      </div>

      <!-- Drawer is choosing a word -->
      <div v-if="state.is_choosing && state.is_drawer" class="space-y-2">
        <p class="text-sm text-muted-foreground">Pick a word to draw:</p>
        <div class="flex flex-wrap gap-2">
          <button
            v-for="w in state.word_choices"
            :key="w"
            type="button"
            @click="chooseWord(w)"
            class="px-3 py-1.5 text-sm rounded-md border bg-card hover:bg-accent-minigame/15 hover:border-accent-minigame/50 transition-colors cursor-pointer font-medium"
          >
            {{ w }}
          </button>
        </div>
      </div>
      <p v-else-if="state.is_choosing" class="text-sm text-muted-foreground italic">
        {{ drawerName }} is choosing a word…
      </p>

      <!-- Reveal: word shown to everyone -->
      <p v-else-if="isReveal" class="text-xl font-bold font-display tracking-wide">
        {{ state.word }}
      </p>

      <!-- Drawing in progress: drawer sees the word, guessers see blanks -->
      <p
        v-else-if="state.is_drawer"
        class="text-xl font-bold font-display tracking-wide text-accent-minigame"
      >
        {{ state.word }}
      </p>
      <p v-else class="text-2xl font-mono tracking-[0.3em] select-none whitespace-pre">
        {{ state.masked }}
      </p>

      <!-- Drawer dropped — turn held briefly for a reconnect (spec §9). -->
      <p
        v-if="state.drawer_away && !isReveal"
        class="text-xs text-amber-500 dark:text-amber-400 italic"
      >
        ⏳ {{ drawerName }} disconnected — holding the turn…
      </p>
    </div>

    <!-- The shared canvas -->
    <DrawingCanvas
      :strokes="state.strokes"
      :is-drawer="state.is_drawer && !state.is_choosing && !isReveal"
      :frozen="isReveal"
      :turn-token="state.turn_token"
      :current_user_id="current_user_id"
    />

    <!-- Guess feed (hidden for the drawer, who can't guess) -->
    <GuessFeed
      v-if="!state.is_drawer"
      :can-guess="
        state.phase === 'turn' && !state.is_choosing && !state.guessed.includes(current_user_id)
      "
      :has-guessed="state.guessed.includes(current_user_id)"
      :turn-token="state.turn_token"
      :current_user_id="current_user_id"
      :name-of="nameOf"
    />

    <HowToPlay game="pictionary" />
  </div>
</template>
