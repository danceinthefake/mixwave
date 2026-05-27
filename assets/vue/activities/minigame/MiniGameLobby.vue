<script setup lang="ts">
// Lobby (features/mini-game.md §1): host picks a game from the
// registry and sets per-game config. The roster lives in the
// chamber's floating presence panel ("Here"), so the lobby doesn't
// duplicate it — it just keeps the "need 2 players" / "waiting" hint.

import { ref } from "vue"
import HowToPlay from "./HowToPlay.vue"

const props = defineProps<{
  game: string
  // Shape differs per game (Pictionary: word_pack/turn_seconds/…;
  // Gartic: step_seconds), so keep it loose at the lobby.
  config: Record<string, any>
  player_count: number
  is_host: boolean
}>()

const emit = defineEmits<{
  "select-game": [game: string]
  "set-config": [config: Record<string, string | number | string[]>]
}>()

// v1 registry: one game. Listed as cards so a second game (Gartic
// Phone, trivia…) is a new entry, not a re-layout.
const GAMES = [
  {
    key: "pictionary",
    label: "Pictionary",
    blurb: "Draw a secret word; everyone else races the clock to guess it.",
  },
  {
    key: "gartic_phone",
    label: "Gartic Phone",
    blurb: "Write → draw → describe down a chain, then watch the books unravel.",
  },
]

const WORD_PACKS = [
  { id: "general", label: "General" },
  { id: "animals", label: "Animals" },
  { id: "movies", label: "Movies" },
  { id: "office", label: "Office" },
  { id: "custom", label: "Custom" },
]
const TURN_SECONDS = [60, 80, 120]
const ROUND_COUNTS = [1, 2, 3, 4, 5]
const STEP_SECONDS = [45, 60, 90]

function setConfig(key: string, value: string | number) {
  if (!props.is_host) return
  emit("set-config", { [key]: value })
}

// Custom-pack textarea: a host-local draft (the server only echoes a
// count, never the words, so it can't be re-synced — re-type after a
// reload). Saving splits on newlines and ships the list to the server.
const customDraft = ref("")
function saveCustom() {
  if (!props.is_host) return
  const words = customDraft.value
    .split(/\r?\n/)
    .map((w) => w.trim())
    .filter(Boolean)
  emit("set-config", { custom_words: words })
}
</script>

<template>
  <div class="max-w-xl mx-auto space-y-3">
    <!-- Game picker — host only. Non-hosts see the "How to play" +
         waiting hint below (the picker title already names the game). -->
    <template v-if="is_host">
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        Choose a game
      </p>

      <div class="grid gap-2">
        <button
          v-for="g in GAMES"
          :key="g.key"
          type="button"
          :aria-pressed="game === g.key"
          @click="emit('select-game', g.key)"
          class="text-left rounded-xl border p-4 transition-all cursor-pointer"
          :class="
            game === g.key
              ? 'border-accent-minigame/60 bg-accent-minigame/10 ring-1 ring-accent-minigame/40'
              : 'bg-card hover:bg-accent border-border'
          "
        >
          <div class="font-semibold font-display">{{ g.label }}</div>
          <div class="text-sm text-muted-foreground">{{ g.blurb }}</div>
        </button>
      </div>
    </template>

    <!-- Per-game config (Pictionary) — host only -->
    <div v-if="game === 'pictionary' && is_host" class="rounded-xl border bg-card/60 p-4 space-y-3">
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">Setup</p>

      <label class="flex items-center justify-between gap-3 text-sm">
        <span class="text-muted-foreground">Word pack</span>
        <select
          :value="config.word_pack"
          :disabled="!is_host"
          @change="(e) => setConfig('word_pack', (e.target as HTMLSelectElement).value)"
          class="px-2 py-1 text-sm rounded-md border bg-card disabled:opacity-60 cursor-pointer"
        >
          <option v-for="p in WORD_PACKS" :key="p.id" :value="p.id">{{ p.label }}</option>
        </select>
      </label>

      <!-- Custom word list (host only). One word/phrase per line. The
           server keeps the words secret (sends back only a count). -->
      <div v-if="config.word_pack === 'custom' && is_host" class="space-y-1">
        <textarea
          v-model="customDraft"
          rows="4"
          placeholder="One word or phrase per line&#10;e.g. rubber duck&#10;merge conflict"
          class="w-full bg-background border border-input rounded-md px-2 py-1.5 text-xs font-mono outline-none focus:border-accent-minigame/60 resize-y"
        ></textarea>
        <div class="flex items-center justify-between">
          <span class="text-[11px] text-muted-foreground">
            {{ config.custom_word_count }} word{{ config.custom_word_count === 1 ? "" : "s" }} saved
          </span>
          <button
            type="button"
            @click="saveCustom"
            class="px-2 py-1 text-xs rounded-md bg-accent-minigame/90 text-white hover:bg-accent-minigame transition-colors cursor-pointer font-medium"
          >
            Save words
          </button>
        </div>
      </div>
      <p v-else-if="config.word_pack === 'custom'" class="text-[11px] text-muted-foreground italic">
        {{ config.custom_word_count }} custom words set by the host.
      </p>

      <label class="flex items-center justify-between gap-3 text-sm">
        <span class="text-muted-foreground">Turn timer</span>
        <select
          :value="config.turn_seconds"
          :disabled="!is_host"
          @change="(e) => setConfig('turn_seconds', Number((e.target as HTMLSelectElement).value))"
          class="px-2 py-1 text-sm rounded-md border bg-card disabled:opacity-60 cursor-pointer"
        >
          <option v-for="s in TURN_SECONDS" :key="s" :value="s">{{ s }}s</option>
        </select>
      </label>

      <label class="flex items-center justify-between gap-3 text-sm">
        <span class="text-muted-foreground">Rounds</span>
        <select
          :value="config.round_count"
          :disabled="!is_host"
          @change="(e) => setConfig('round_count', Number((e.target as HTMLSelectElement).value))"
          class="px-2 py-1 text-sm rounded-md border bg-card disabled:opacity-60 cursor-pointer"
        >
          <option v-for="r in ROUND_COUNTS" :key="r" :value="r">{{ r }}</option>
        </select>
      </label>
    </div>

    <!-- Per-game config (Gartic Phone) — host only -->
    <div
      v-if="game === 'gartic_phone' && is_host"
      class="rounded-xl border bg-card/60 p-4 space-y-3"
    >
      <p class="text-xs uppercase tracking-wider text-muted-foreground font-display">Setup</p>
      <label class="flex items-center justify-between gap-3 text-sm">
        <span class="text-muted-foreground">Time per step</span>
        <select
          :value="config.step_seconds"
          :disabled="!is_host"
          @change="(e) => setConfig('step_seconds', Number((e.target as HTMLSelectElement).value))"
          class="px-2 py-1 text-sm rounded-md border bg-card disabled:opacity-60 cursor-pointer"
        >
          <option v-for="s in STEP_SECONDS" :key="s" :value="s">{{ s }}s</option>
        </select>
      </label>
      <p class="text-[11px] text-muted-foreground">
        One round per player: write a phrase, draw the one you're handed, describe the next… then
        the whole chain is revealed.
      </p>
    </div>

    <!-- How to play — host only in the lobby (the players reading the
         rules mid-game see it on the stage instead). -->
    <HowToPlay v-if="is_host" :game="game" />

    <!-- Start gate / waiting hint -->
    <p v-if="player_count < 2" class="text-xs text-muted-foreground italic text-center pt-1">
      Need at least 2 players to start. Share the chamber link to invite more.
    </p>
    <p v-else-if="!is_host" class="text-xs text-muted-foreground italic text-center pt-1">
      Waiting for the host to start the game.
    </p>
  </div>
</template>
