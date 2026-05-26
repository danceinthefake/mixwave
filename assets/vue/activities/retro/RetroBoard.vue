<script setup lang="ts">
// Top-level retro board. Phase-routes between Setup (column-name
// editor) and the columns view; columns view stays mounted from
// :brainstorm through :archived (cards become visible at :reveal,
// votes layer on at :voting, action items at :discuss).
//
// See features/retrospective.md for the full design.

import { computed, provide, ref } from "vue"
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

export type RetroReaction = {
  user_id: string | null
  emoji: string
}

export type RetroComment = {
  id: string
  body: string
  author_user_id: string | null
  author_alias: string
  author_display_name: string | null
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
  // Emoji reactions (multi-emoji, one-per-user-per-emoji
  // toggle). Empty when nobody's reacted yet.
  reactions: RetroReaction[]
  // Flat comments thread. Collapsed by default in the UI;
  // expand to see / add.
  comments: RetroComment[]
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

type LastArchived = {
  id: string
  title: string | null
  archived_at: string | null
} | null

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
  // Most-recent archived retro for this chamber (or null).
  // Powers the "Last retro archived → Copy share link" notice
  // that shows in the empty-retro state so hosts can grab the
  // permalink immediately after clicking Archive.
  last_archived: LastArchived
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

// Stepper model — the canonical retro flow in display order.
// `voting` is dimmed when the host hasn't opted into voting at
// :setup. Each step's index relative to the current phase tells
// us "done / current / upcoming" for visual state.
const STEPPER_PHASES: { phase: RetroPhase; label: string }[] = [
  { phase: "setup", label: "Setup" },
  { phase: "brainstorm", label: "Brainstorm" },
  { phase: "reveal", label: "Reveal" },
  { phase: "voting", label: "Voting" },
  { phase: "discuss", label: "Discuss" },
  { phase: "archived", label: "Archived" },
]

const currentPhaseIndex = computed(() =>
  phase.value ? STEPPER_PHASES.findIndex((s) => s.phase === phase.value) : -1,
)

function stepperState(idx: number, stepPhase: RetroPhase) {
  // Voting is dimmed-and-skipped when voting_enabled is false —
  // still rendered for orientation (you can see the phase
  // exists, just not for this run) but de-emphasised.
  const votingSkipped = stepPhase === "voting" && !(props.session?.voting_enabled ?? false)
  if (idx === currentPhaseIndex.value) return "current"
  if (idx < currentPhaseIndex.value) return votingSkipped ? "skipped" : "done"
  return votingSkipped ? "skipped" : "upcoming"
}

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

// Permalink for the archived view. Outlives the chamber — see
// /archives/retros/:id route + the chamber_id-nullable FK on
// retro_sessions. Used both for the in-board banner (when
// session.status = "archived") and the empty-state notice
// (which targets last_archived.id, the most-recent past retro).
function buildPermalink(id: string) {
  return `${window.location.origin}/archives/retros/${id}`
}
const permalink = computed(() => (props.session ? buildPermalink(props.session.id) : ""))
const lastArchivedPermalink = computed(() =>
  props.last_archived ? buildPermalink(props.last_archived.id) : "",
)

const copiedFlash = ref(false)
async function copyText(text: string) {
  try {
    await navigator.clipboard.writeText(text)
    copiedFlash.value = true
    setTimeout(() => (copiedFlash.value = false), 1500)
  } catch {
    /* clipboard blocked — silent fail; bookmark via the past-retros disclosure */
  }
}
async function copyPermalink() {
  await copyText(permalink.value)
}
async function copyLastArchivedPermalink() {
  await copyText(lastArchivedPermalink.value)
}
</script>

<template>
  <div class="space-y-6">
    <header class="space-y-3">
      <h1 class="text-2xl font-bold tracking-tight font-display brand-gradient-text">
        {{ session?.title || "Retrospective" }}
      </h1>

      <!-- Phase stepper. Shows where the team is in the 5-or-6
           step flow at a glance. Voting step de-emphasises
           when the host hasn't enabled voting for this run. -->
      <ol
        v-if="session"
        class="flex flex-wrap items-center gap-x-1 gap-y-1.5 text-[11px]"
        :aria-label="`Retro phase: ${session.status}`"
      >
        <template v-for="(step, idx) in STEPPER_PHASES" :key="step.phase">
          <li class="flex items-center gap-1.5">
            <span
              aria-hidden="true"
              class="inline-flex items-center justify-center size-4 rounded-full text-[10px] font-mono shrink-0 transition-colors"
              :class="{
                'bg-accent-bass text-background ring-2 ring-accent-bass/40 ring-offset-1 ring-offset-background':
                  stepperState(idx, step.phase) === 'current',
                'bg-accent-bass/60 text-background': stepperState(idx, step.phase) === 'done',
                'border border-input bg-card text-muted-foreground':
                  stepperState(idx, step.phase) === 'upcoming',
                'border border-dashed border-input bg-card text-muted-foreground/50':
                  stepperState(idx, step.phase) === 'skipped',
              }"
            >
              {{ stepperState(idx, step.phase) === "done" ? "✓" : idx + 1 }}
            </span>
            <span
              class="font-medium"
              :class="{
                'text-foreground': stepperState(idx, step.phase) === 'current',
                'text-muted-foreground': stepperState(idx, step.phase) !== 'current',
                'line-through opacity-60': stepperState(idx, step.phase) === 'skipped',
              }"
            >
              {{ step.label }}
            </span>
          </li>
          <li
            v-if="idx < STEPPER_PHASES.length - 1"
            aria-hidden="true"
            class="text-muted-foreground/40 select-none"
          >
            ›
          </li>
        </template>
      </ol>
    </header>

    <!-- Collapsible process guide. Helps first-time users (and
         occasional ones who've forgotten the flow) without
         taking real-estate from the board. Closed by default. -->
    <details class="rounded-lg border bg-card/40 group">
      <summary
        class="cursor-pointer px-3 py-2 text-xs font-medium text-muted-foreground hover:text-foreground flex items-center justify-between"
      >
        <span>How retros work</span>
        <span aria-hidden="true" class="group-open:rotate-90 transition-transform">›</span>
      </summary>
      <div class="px-4 pb-3 pt-1 text-xs text-muted-foreground space-y-2 leading-relaxed">
        <p>
          A retro walks through 5 or 6 phases. The host advances; everyone else writes, reacts,
          votes, and comments.
        </p>
        <ol class="space-y-1.5 list-decimal pl-5">
          <li>
            <span class="font-semibold text-foreground">Setup</span> — host renames columns, decides
            whether to enable voting and "show all cards live." Locked at the next click.
          </li>
          <li>
            <span class="font-semibold text-foreground">Brainstorm</span> — everyone adds cards. By
            default each person sees only their own + face-down placeholders for others'.
            Live-visible mode shows everything as it lands.
          </li>
          <li>
            <span class="font-semibold text-foreground">Reveal</span> — all cards become visible.
            Read the room. React with emojis, comment to dig in.
          </li>
          <li>
            <span class="font-semibold text-foreground">Voting</span>
            <span class="italic">(opt-in)</span> — each person spends 3 dots across the cards.
            Useful when you have too many to discuss linearly (~15+).
          </li>
          <li>
            <span class="font-semibold text-foreground">Discuss</span> — cards sort by vote count.
            Host can highlight a card as currently-discussing; anyone adds action items (tied to a
            card or freeform).
          </li>
          <li>
            <span class="font-semibold text-foreground">Archived</span> — session frozen. Permanent
            link survives the chamber being reaped. Start a new retro in the same chamber when
            ready.
          </li>
        </ol>
        <p class="pt-1">
          <span class="font-semibold text-foreground">Tips:</span>
          ≥15 cards → enable voting · small high-trust team → turn on "show all live" in setup ·
          creator can promote co-hosts (presence panel) so anyone can advance the phase.
        </p>
      </div>
    </details>

    <!-- No active session — but if there's a recently-archived
         one in this chamber, surface the share link so the host
         can grab it without hunting through the past-retros
         disclosure. -->
    <div
      v-if="!session && last_archived"
      class="rounded-xl border border-accent-bass/40 bg-accent-bass/10 px-4 py-3 flex flex-wrap items-center gap-3"
      role="status"
    >
      <div class="text-xs space-y-0.5 flex-1 min-w-0">
        <p class="font-semibold text-foreground">
          Last retro archived: {{ last_archived.title || "Untitled retro" }}
        </p>
        <p class="text-muted-foreground">
          Permanent link kept. Share or bookmark before the chamber idles out.
        </p>
      </div>
      <button
        type="button"
        @click="copyLastArchivedPermalink"
        class="rounded-md bg-accent-bass text-background px-3 py-1.5 text-xs font-medium hover:bg-accent-bass/90 shrink-0"
      >
        {{ copiedFlash ? "Copied!" : "Copy share link" }}
      </button>
    </div>

    <!-- No session yet -->
    <div v-if="!session && is_host" class="rounded-xl border bg-card p-6 space-y-3">
      <p class="text-sm text-muted-foreground">
        {{
          last_archived
            ? "Ready for the next retro?"
            : "No retro session running. Start one to begin."
        }}
      </p>
      <button
        type="button"
        @click="startSession"
        class="rounded-md bg-accent-bass text-background px-4 py-2 text-sm font-medium hover:bg-accent-bass/90"
      >
        {{ last_archived ? "Start new retro" : "Start retro" }}
      </button>
    </div>

    <div
      v-else-if="!session"
      class="rounded-xl border bg-card p-6 text-sm text-muted-foreground italic"
    >
      Waiting for the host to start the retro.
    </div>

    <!-- :setup — column-name + title editor -->
    <RetroSetup v-else-if="phase === 'setup'" :session="session" :is_host="is_host" />

    <!-- :brainstorm / :reveal / :voting / :discuss / :archived — columns grid -->
    <div v-else class="space-y-4">
      <!-- Permalink banner — shown the moment the retro is
           archived, so the host can grab the shareable URL
           before the chamber idles out. Survives chamber
           reaping; the /archives/retros/:id route loads
           straight from Postgres. URL isn't surfaced visually
           — one click copies it to clipboard, the "Copied!"
           flash confirms. -->
      <div
        v-if="session.status === 'archived'"
        class="rounded-xl border border-accent-bass/40 bg-accent-bass/10 px-4 py-3 flex flex-wrap items-center gap-3"
        role="status"
      >
        <div class="text-xs space-y-0.5 flex-1 min-w-0">
          <p class="font-semibold text-foreground">Retro archived · permanent link</p>
          <p class="text-muted-foreground">
            Bookmark to revisit. The chamber will eventually be reaped; this URL keeps working.
          </p>
        </div>
        <button
          type="button"
          @click="copyPermalink"
          class="rounded-md bg-accent-bass text-background px-3 py-1.5 text-xs font-medium hover:bg-accent-bass/90 shrink-0"
        >
          {{ copiedFlash ? "Copied!" : "Copy share link" }}
        </button>
      </div>

      <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-3 lg:gap-4">
        <RetroColumn
          v-for="col in session.columns"
          :key="col.id"
          :column="col"
          :cards="visibleCardsByColumnId[col.id] ?? []"
          :total_count="countsByColumnId[col.id] ?? 0"
          :hidden_count="hiddenCountByColumnId[col.id] ?? 0"
          :phase="phase!"
          :brainstorm_visible="session.brainstorm_visible"
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

    <RetroHostControls v-if="session && is_host" :session="session" :is_host="is_host" />
  </div>
</template>
