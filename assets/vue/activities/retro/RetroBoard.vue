<script setup lang="ts">
// Top-level retro board. Phase-routes between Setup (column-name
// editor) and the columns view; columns view stays mounted from
// :brainstorm through :archived (cards become visible at :reveal,
// votes layer on at :voting, action items at :discuss).
//
// See features/retrospective.md for the full design.

import { computed } from "vue"
import { useLiveVue } from "live_vue"
import RetroSetup from "./RetroSetup.vue"
import RetroColumn from "./RetroColumn.vue"
import RetroDiscussPanel from "./RetroDiscussPanel.vue"
import RetroVotingPanel from "./RetroVotingPanel.vue"
import RetroHostControls from "./RetroHostControls.vue"

export type RetroPhase = "setup" | "brainstorm" | "reveal" | "voting" | "discuss" | "archived"

export type RetroColumnT = {
  id: string
  name: string
  position: number
}

export type RetroCard = {
  id: string
  retro_column_id: string
  body: string
  author_user_id: string | null
  author_alias: string
  vote_count: number
}

export type RetroActionItem = {
  id: string
  source_card_id: string | null
  body: string
  assignee_alias: string | null
  due_date: string | null
  completed: boolean
}

export type RetroSession = {
  id: string
  title: string | null
  status: RetroPhase
  voting_enabled: boolean
  columns: RetroColumnT[]
  cards: RetroCard[]
  action_items: RetroActionItem[]
}

const VOTE_CAP = 3

const props = defineProps<{
  chamber_slug: string
  session: RetroSession | null
  tallies: Record<string, number>
  my_votes: string[]
  current_user_id: string
  current_user_alias: string
  is_host: boolean
}>()

const live = useLiveVue()

const phase = computed<RetroPhase | null>(() => props.session?.status ?? null)

// Cards grouped by column id, sorted by:
//   - vote_count desc in :discuss / :archived (after materialisation)
//   - insertion order elsewhere (session.cards already comes in
//     ascending inserted_at from the LV's preload)
const cardsByColumnId = computed(() => {
  const grouped: Record<string, RetroCard[]> = {}
  if (!props.session) return grouped

  for (const col of props.session.columns) {
    grouped[col.id] = []
  }
  for (const card of props.session.cards) {
    if (!grouped[card.retro_column_id]) grouped[card.retro_column_id] = []
    grouped[card.retro_column_id].push(card)
  }

  if (phase.value === "discuss" || phase.value === "archived") {
    for (const col of props.session.columns) {
      grouped[col.id].sort((a, b) => b.vote_count - a.vote_count)
    }
  }

  return grouped
})

// During :brainstorm participants only see their own cards
// (spec §4). The host has no special card-visibility privilege.
const visibleCardsByColumnId = computed(() => {
  if (phase.value !== "brainstorm") return cardsByColumnId.value

  const filtered: Record<string, RetroCard[]> = {}
  for (const [colId, cards] of Object.entries(cardsByColumnId.value)) {
    filtered[colId] = cards.filter((c) => c.author_user_id === props.current_user_id)
  }
  return filtered
})

// Card count per column, visible to everyone during :brainstorm
// so the room can gauge pace without reading content.
const countsByColumnId = computed(() => {
  const counts: Record<string, number> = {}
  for (const [colId, cards] of Object.entries(cardsByColumnId.value)) {
    counts[colId] = cards.length
  }
  return counts
})

// During :brainstorm, the gap between everyone's cards and the
// viewer's own cards. Rendered in each column as N face-down
// silhouettes so participants can see at a glance that others
// are contributing — mirrors poker's voted-but-unrevealed card
// silhouettes. Empty/zero outside :brainstorm.
const hiddenCountByColumnId = computed(() => {
  const counts: Record<string, number> = {}
  if (phase.value !== "brainstorm") return counts

  for (const col of props.session?.columns ?? []) {
    const total = (cardsByColumnId.value[col.id] ?? []).length
    const visible = (visibleCardsByColumnId.value[col.id] ?? []).length
    counts[col.id] = Math.max(0, total - visible)
  }
  return counts
})

const myVoteSet = computed(() => new Set(props.my_votes))
const votesRemaining = computed(() => VOTE_CAP - myVoteSet.value.size)

function startSession() {
  live.pushEvent("retro_start_session", {})
}
</script>

<template>
  <div class="space-y-6">
    <header class="flex items-baseline justify-between gap-4">
      <div>
        <h1 class="text-2xl font-bold tracking-tight font-display brand-gradient-text">
          {{ session?.title || "Retrospective" }}
        </h1>
        <p v-if="session" class="text-xs uppercase tracking-wider text-muted-foreground mt-1">
          {{ session.status }}<span v-if="session.voting_enabled"> · voting</span>
        </p>
      </div>
    </header>

    <!-- No session yet -->
    <div v-if="!session && is_host" class="rounded-xl border bg-card p-6 space-y-3">
      <p class="text-sm text-muted-foreground">
        No retro session running. Start one to begin.
      </p>
      <button
        type="button"
        @click="startSession"
        class="rounded-md bg-accent-bass text-background px-4 py-2 text-sm font-medium hover:bg-accent-bass/90"
      >
        Start retro
      </button>
    </div>

    <div
      v-else-if="!session"
      class="rounded-xl border bg-card p-6 text-sm text-muted-foreground italic"
    >
      Waiting for the host to start the retro.
    </div>

    <!-- :setup — column-name + title editor -->
    <RetroSetup
      v-else-if="phase === 'setup'"
      :session="session"
      :is_host="is_host"
    />

    <!-- :brainstorm / :reveal / :voting / :discuss / :archived — columns grid -->
    <div v-else class="space-y-4">
      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 lg:gap-4">
        <RetroColumn
          v-for="col in session.columns"
          :key="col.id"
          :column="col"
          :cards="visibleCardsByColumnId[col.id] ?? []"
          :total_count="countsByColumnId[col.id] ?? 0"
          :hidden_count="hiddenCountByColumnId[col.id] ?? 0"
          :phase="phase!"
          :is_host="is_host"
          :current_user_id="current_user_id"
          :tallies="tallies"
          :my_votes="myVoteSet"
          :votes_remaining="votesRemaining"
        />
      </div>

      <RetroVotingPanel
        v-if="phase === 'voting'"
        :votes_remaining="votesRemaining"
        :vote_cap="VOTE_CAP"
      />

      <RetroDiscussPanel
        v-if="phase === 'discuss' || phase === 'archived'"
        :session="session"
        :is_host="is_host"
      />
    </div>

    <RetroHostControls
      v-if="session && is_host"
      :session="session"
      :is_host="is_host"
    />
  </div>
</template>
