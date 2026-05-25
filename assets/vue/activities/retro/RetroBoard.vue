<script setup lang="ts">
// Top-level retro board. Phase-routes between Setup (column-name
// editor) and the columns view; columns view stays mounted from
// :brainstorm through :archived (cards become visible at :reveal,
// votes layer on at :voting, action items at :discuss).
//
// See features/retrospective.md for the full design.

import { computed, provide } from "vue"
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
  // Primary identity label snapshotted at create time:
  // user.alias when set, else user.display_name. Always non-null.
  author_alias: string
  // Underlying noun-adj-NN handle snapshotted at create time.
  // Nullable for cards predating the column. When present and
  // different from author_alias, rendered as the "· …" tail
  // (matches poker reveal's two-piece pattern; spec §3).
  author_display_name: string | null
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
  // When true: all cards visible to everyone during :brainstorm.
  // When false (default): each participant sees only their own
  // cards until host advances to :reveal.
  brainstorm_visible: boolean
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
  // Host's currently-focused card during :discuss. nil = no focus.
  // Surfaced as a ring + scale highlight on the matching card so
  // the room knows which one is being talked about.
  discussing_card_id: string | null
  // Current chamber participants' alias_or_name strings. Provided
  // to descendants via inject so RetroActionRow / RetroDiscussPanel
  // can offer assignee autocomplete without prop-drilling.
  participant_aliases: string[]
  current_user_id: string
  current_user_alias: string
  is_host: boolean
}>()

// Make the participant list available to any descendant (action
// rows + the discuss panel's add form). Cheap to provide a
// computed ref so descendants react when presence changes.
provide(
  "retro_participant_aliases",
  computed(() => props.participant_aliases),
)

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
// (spec §4) — unless the host opted into brainstorm_visible at
// :setup, in which case everyone sees everything live.
const visibleCardsByColumnId = computed(() => {
  if (phase.value !== "brainstorm") return cardsByColumnId.value
  if (props.session?.brainstorm_visible) return cardsByColumnId.value

  const filtered: Record<string, RetroCard[]> = {}
  for (const [colId, cards] of Object.entries(cardsByColumnId.value)) {
    filtered[colId] = cards.filter((c) => c.author_user_id === props.current_user_id)
  }
  return filtered
})

// Action items grouped by source card id. Tied actions appear
// nested under their card during :discuss / :archived (spec §6).
// Freeform actions (source_card_id == null) bucket under the
// special key "__freeform__" for RetroDiscussPanel to pick up.
const actionsByCardId = computed(() => {
  const grouped: Record<string, RetroActionItem[]> = { __freeform__: [] }
  if (!props.session) return grouped
  for (const action of props.session.action_items) {
    if (action.source_card_id) {
      if (!grouped[action.source_card_id]) grouped[action.source_card_id] = []
      grouped[action.source_card_id].push(action)
    } else {
      grouped.__freeform__.push(action)
    }
  }
  return grouped
})

const freeformActions = computed(() => actionsByCardId.value.__freeform__ ?? [])

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
          :discussing_card_id="discussing_card_id"
          :actions_by_card_id="actionsByCardId"
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
        :freeform_actions="freeformActions"
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
