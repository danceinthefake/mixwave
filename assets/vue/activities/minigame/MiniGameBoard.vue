<script setup lang="ts">
// Top-level Vue island for a mini-game chamber. Mounted by Chamber.vue
// when `chamber.activity === "minigame"`. The mini-game is a
// *framework* (features/mini-game.md §1): this board owns the lobby +
// host-control shell and routes the middle to the chosen game's stage
// (Pictionary or Gartic Phone).
//
// State flows in from the LiveView; user actions push back as Phoenix
// events. The chamber GenServer broadcasts on every change, so every
// player's board re-renders within ~50ms.

import { computed, watch } from "vue"
import { useLiveVue } from "live_vue"
import { playGameOver } from "../../lib/audio"
import MiniGameLobby from "./MiniGameLobby.vue"
import MiniGameScoreboard from "./MiniGameScoreboard.vue"
import MiniGameHostControls from "./MiniGameHostControls.vue"
import PictionaryStage from "./pictionary/PictionaryStage.vue"
import GarticStage from "./gartic_phone/GarticStage.vue"

export type MiniGamePhase = "lobby" | "turn" | "turn_reveal" | "gameover"

export type MiniGameConfig = {
  word_pack: string
  turn_seconds: number
  round_count: number
  custom_word_count: number
}

export type Stroke = {
  seq?: number
  points: [number, number][]
  color: string
  width: number
}

// Pictionary per-user view.
export type MiniGameView = {
  game: "pictionary"
  phase: MiniGamePhase
  config: MiniGameConfig
  round: number
  round_count: number
  players: string[]
  drawer_id: string | null
  is_drawer: boolean
  is_choosing: boolean
  word: string | null
  masked: string
  drawer_away: boolean
  word_choices: string[]
  guessed: string[]
  scores: Record<string, number>
  deadline: number | null
  strokes: Stroke[]
  turn_token: number
}

export type GarticEntry =
  | { kind: "text"; by: string; text: string }
  | { kind: "drawing"; by: string; strokes: Stroke[] }

// Gartic Phone per-user view (private during play, public at album).
export type GarticView = {
  game: "gartic_phone"
  phase: "lobby" | "play" | "album" | "gameover"
  config?: { step_seconds: number }
  // play
  step?: number
  total_steps?: number
  player_count?: number
  submitted_count?: number
  deadline?: number | null
  turn_token?: number
  is_player?: boolean
  my_kind?: "text" | "drawing" | null
  prompt?: GarticEntry | null
  submitted?: boolean
  // album
  total_books?: number
  album_book?: number
  album_page?: number
  book_owner?: string
  pages?: GarticEntry[]
  // gameover
  books?: { owner: string; pages: GarticEntry[] }[]
}

export type Participant = {
  user_id: string
  display_name: string
  alias: string | null
}

const props = defineProps<{
  state: MiniGameView | GarticView | null
  participants: Participant[]
  current_user_id: string
  is_host: boolean
}>()

const live = useLiveVue()

const state = computed(() => props.state)
const game = computed(() => state.value?.game ?? null)
const phase = computed(() => state.value?.phase ?? null)

// Narrowed views per game so the template stays type-safe.
const pict = computed(() => (game.value === "pictionary" ? (state.value as MiniGameView) : null))
const gartic = computed(() => (game.value === "gartic_phone" ? (state.value as GarticView) : null))

const pictPlaying = computed(
  () => !!pict.value && (phase.value === "turn" || phase.value === "turn_reveal"),
)
const garticActive = computed(() => !!gartic.value && phase.value !== "lobby")

// alias_or_name lookup for rendering players without leaking raw ids.
const nameOf = computed(() => {
  const map = new Map(props.participants.map((p) => [p.user_id, p.alias || p.display_name]))
  return (id: string | null): string => {
    if (!id) return "—"
    return map.get(id) ?? `${id.slice(0, 4)}…`
  }
})

const drawerName = computed(() => nameOf.value(pict.value?.drawer_id ?? null))

// Fewest players the selected game needs to start (server-sourced).
const minPlayers = computed(() => (state.value as any)?.min_players ?? 2)

// Celebratory fanfare the moment any game ends.
watch(phase, (next, prev) => {
  if (next === "gameover" && prev && prev !== "gameover") void playGameOver()
})
</script>

<template>
  <section
    v-if="state"
    class="minigame-scope w-full max-w-3xl mx-auto space-y-4"
    aria-label="Mini-game board"
  >
    <!-- Header: game name + (Pictionary) round status + host controls -->
    <header class="flex items-center justify-between gap-3 flex-wrap">
      <div class="flex items-center gap-2">
        <span class="size-2.5 rounded-full bg-accent-minigame"></span>
        <h2 class="text-lg font-bold font-display tracking-tight">Mini-game</h2>
        <span
          v-if="pictPlaying"
          class="text-xs uppercase tracking-wider text-muted-foreground tabular-nums"
        >
          Round {{ pict!.round }} / {{ pict!.round_count }}
        </span>
      </div>
      <MiniGameHostControls
        v-if="is_host"
        :phase="phase ?? 'lobby'"
        :player_count="participants.length"
        :min_players="minPlayers"
        @start="live.pushEvent('minigame_start', {})"
        @skip="live.pushEvent('minigame_skip', {})"
        @next="live.pushEvent('minigame_next', {})"
        @play-again="live.pushEvent('minigame_play_again', {})"
        @end="live.pushEvent('minigame_end', {})"
      />
    </header>

    <!-- Lobby: game picker + config -->
    <MiniGameLobby
      v-if="phase === 'lobby'"
      :game="game ?? 'pictionary'"
      :config="(state as any).config"
      :player_count="participants.length"
      :min_players="minPlayers"
      :is_host="is_host"
      @select-game="(g) => live.pushEvent('minigame_select_game', { game: g })"
      @set-config="(c) => live.pushEvent('minigame_set_config', { config: c })"
    />

    <!-- Pictionary: scoreboard strip + stage -->
    <div v-else-if="pictPlaying" class="space-y-4">
      <MiniGameScoreboard
        :scores="pict!.scores"
        :players="pict!.players"
        :drawer_id="pict!.drawer_id"
        :guessed="pict!.guessed"
        :name-of="nameOf"
      />
      <PictionaryStage
        :state="pict!"
        :current_user_id="current_user_id"
        :drawer-name="drawerName"
        :name-of="nameOf"
      />
    </div>

    <!-- Pictionary game over: final scoreboard -->
    <div v-else-if="pict && phase === 'gameover'" class="space-y-4">
      <div class="text-center space-y-1">
        <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">Game over</p>
        <h3 class="text-2xl font-bold font-display">Final scores</h3>
      </div>
      <MiniGameScoreboard
        :scores="pict!.scores"
        :players="pict!.players"
        :drawer_id="null"
        :guessed="[]"
        :name-of="nameOf"
        final
      />
      <p v-if="!is_host" class="text-center text-sm text-muted-foreground">
        Waiting for the host to play again or end the game.
      </p>
    </div>

    <!-- Gartic Phone: play / album / gameover all live in the stage -->
    <GarticStage
      v-else-if="garticActive"
      :state="gartic!"
      :current_user_id="current_user_id"
      :is_host="is_host"
      :name-of="nameOf"
    />
  </section>

  <section v-else class="max-w-md mx-auto text-center py-16 text-muted-foreground">
    No game running.
  </section>
</template>
