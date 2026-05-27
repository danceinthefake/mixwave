<script setup lang="ts">
// Two Truths and a Lie stage. Phases:
//   writing  — type 2 truths + 1 lie, mark the lie, submit (private).
//   guessing — one author at a time; everyone else picks the lie.
//   reveal   — the lie + scores are shown; host advances.
//   gameover — final scoreboard.
// Reuses MiniGameScoreboard (scores) + HowToPlay.

import { computed, onUnmounted, ref, watch } from "vue"
import { useLiveVue } from "live_vue"
import type { TwoTruthsView } from "../MiniGameBoard.vue"
import MiniGameScoreboard from "../MiniGameScoreboard.vue"
import HowToPlay from "../HowToPlay.vue"

const props = defineProps<{
  state: TwoTruthsView
  current_user_id: string
  is_host: boolean
  nameOf: (id: string | null) => string
}>()

const live = useLiveVue()

// --- writing draft (local until submit), reset each phase ---
const items = ref(["", "", ""])
const lieIdx = ref(0)
watch(
  () => props.state.turn_token,
  () => {
    items.value = ["", "", ""]
    lieIdx.value = 0
  },
)

// --- countdown from the absolute deadline (writing + guessing) ---
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

const canSubmitWriting = computed(() => items.value.every((t) => t.trim().length > 0))

function submitStatements() {
  if (!canSubmitWriting.value) return
  live.pushEvent("minigame_submit", { items: items.value.map((t) => t.trim()), lie: lieIdx.value })
}

function guessLie(i: number) {
  if (props.state.is_author || props.state.my_guess != null) return
  live.pushEvent("minigame_submit", { lie_guess: i })
}

const authorName = computed(() => props.nameOf(props.state.author ?? null))
// My pick + result during reveal.
const myPick = computed(() => props.state.picks?.[props.current_user_id])
const spotters = computed(
  () =>
    Object.entries(props.state.picks ?? {}).filter(([, p]) => p === props.state.lie_index).length,
)
</script>

<template>
  <div class="space-y-4">
    <!-- ===================== WRITING ===================== -->
    <div v-if="state.phase === 'writing'" class="space-y-3">
      <div class="flex items-center justify-between gap-3 flex-wrap">
        <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
          Two truths and a lie
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

      <p
        v-if="state.is_player === false"
        class="text-sm text-muted-foreground italic text-center py-8"
      >
        Watching this round — you'll join the next game.
      </p>

      <div
        v-else-if="state.submitted"
        class="rounded-xl border bg-card/60 p-6 text-center space-y-1"
      >
        <p class="text-lg font-display font-semibold">Locked in ✓</p>
        <p class="text-sm text-muted-foreground">
          Waiting for everyone… {{ state.submitted_count }}/{{ state.player_count }}
        </p>
      </div>

      <div v-else class="space-y-2">
        <p class="text-sm text-muted-foreground">
          Write three statements about yourself — two true, one lie. Mark the lie with the dot.
        </p>
        <label
          v-for="(_, i) in items"
          :key="i"
          class="flex items-center gap-2 rounded-lg border bg-card/60 px-2.5 py-1.5"
          :class="lieIdx === i ? 'border-accent-minigame/60' : 'border-border'"
        >
          <input
            type="radio"
            name="lie"
            :checked="lieIdx === i"
            @change="lieIdx = i"
            class="accent-accent-minigame shrink-0"
            :title="`Mark statement ${i + 1} as the lie`"
          />
          <input
            v-model="items[i]"
            type="text"
            maxlength="120"
            :placeholder="`Statement ${i + 1}${lieIdx === i ? ' (the lie)' : ''}`"
            class="flex-1 bg-transparent text-sm outline-none"
          />
        </label>
        <div class="flex justify-end">
          <button
            type="button"
            :disabled="!canSubmitWriting"
            @click="submitStatements"
            class="px-4 py-1.5 text-sm rounded-md bg-primary text-primary-foreground hover:bg-primary/90 cursor-pointer font-medium disabled:opacity-50 disabled:cursor-not-allowed"
          >
            Submit
          </button>
        </div>
      </div>

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

    <!-- ===================== GUESSING / REVEAL ===================== -->
    <div v-else-if="state.phase === 'guessing' || state.phase === 'reveal'" class="space-y-4">
      <MiniGameScoreboard
        :scores="state.scores ?? {}"
        :players="state.players ?? []"
        :drawer_id="state.author ?? null"
        :guessed="state.guessed ?? []"
        :name-of="nameOf"
      />

      <div class="flex items-center justify-between gap-3 flex-wrap">
        <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
          {{ (state.author_index ?? 0) + 1 }} / {{ state.total_authors }} ·
          <span class="text-foreground font-semibold">{{ authorName }}</span>
        </p>
        <div class="flex items-center gap-3">
          <span
            v-if="state.phase === 'guessing'"
            class="text-xs text-muted-foreground tabular-nums"
          >
            {{ state.guessed_count }}/{{ state.guesser_count }} guessed
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

      <p v-if="state.phase === 'guessing'" class="text-sm">
        <template v-if="state.is_author"
          >Your statements — the room is hunting your lie 👀</template
        >
        <template v-else-if="state.my_guess != null">Locked in — waiting for the reveal…</template>
        <template v-else
          >Which one is <span class="font-semibold">{{ authorName }}</span
          >'s lie?</template
        >
      </p>
      <p v-else class="text-sm">
        <span class="font-semibold text-accent-minigame">{{ spotters }}</span> spotted the lie.
        <template v-if="!state.is_author && myPick != null">
          You {{ myPick === state.lie_index ? "got it! 🎯" : "were fooled." }}
        </template>
      </p>

      <!-- The three statements -->
      <ul class="space-y-2">
        <li v-for="(text, i) in state.statements ?? []" :key="i">
          <button
            type="button"
            :disabled="state.phase === 'reveal' || state.is_author || state.my_guess != null"
            @click="guessLie(i)"
            class="w-full text-left rounded-lg border px-3 py-2.5 text-sm transition-colors"
            :class="[
              state.phase === 'reveal' && i === state.lie_index
                ? 'border-destructive/60 bg-destructive/10'
                : state.phase === 'reveal'
                  ? 'border-success/50 bg-success/10'
                  : state.my_guess === i
                    ? 'border-accent-minigame/60 bg-accent-minigame/10'
                    : 'border-border bg-card/60',
              state.phase === 'guessing' && !state.is_author && state.my_guess == null
                ? 'hover:bg-accent cursor-pointer'
                : 'cursor-default',
            ]"
          >
            <span class="flex items-center justify-between gap-2">
              <span>{{ text }}</span>
              <span
                v-if="state.phase === 'reveal' && i === state.lie_index"
                class="text-xs font-semibold text-destructive shrink-0"
              >
                THE LIE
              </span>
              <span v-else-if="state.phase === 'reveal'" class="text-xs text-success shrink-0"
                >truth</span
              >
              <span v-else-if="state.my_guess === i" class="text-xs text-accent-minigame shrink-0"
                >your pick</span
              >
            </span>
          </button>
        </li>
      </ul>

      <!-- Host advance -->
      <div v-if="is_host" class="flex justify-center">
        <button
          type="button"
          @click="live.pushEvent('minigame_skip', {})"
          class="px-4 py-1.5 text-sm rounded-md font-medium cursor-pointer transition-colors"
          :class="
            state.phase === 'reveal'
              ? 'bg-primary text-primary-foreground hover:bg-primary/90'
              : 'border bg-card hover:bg-accent text-muted-foreground'
          "
        >
          {{ state.phase === "reveal" ? "Next →" : "Skip the wait →" }}
        </button>
      </div>
    </div>

    <!-- ===================== GAME OVER ===================== -->
    <div v-else-if="state.phase === 'gameover'" class="space-y-4">
      <div class="text-center space-y-1">
        <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">Game over</p>
        <h3 class="text-2xl font-bold font-display">Final scores</h3>
      </div>
      <MiniGameScoreboard
        :scores="state.scores ?? {}"
        :players="state.players ?? []"
        :drawer_id="null"
        :guessed="[]"
        :name-of="nameOf"
        final
      />
      <p v-if="!is_host" class="text-center text-sm text-muted-foreground">
        Waiting for the host to play again or end.
      </p>
    </div>

    <HowToPlay v-if="state.phase !== 'gameover'" game="two_truths" />
  </div>
</template>
