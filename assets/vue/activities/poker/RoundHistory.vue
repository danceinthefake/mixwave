<script setup lang="ts">
// Collapsed list of finished rounds in this chamber. Renders only
// when the session has at least one completed round; the host
// pushes a round into history every time they click "Next round"
// (server side, in PokerSession.next_round/2). Re-vote does NOT
// push — the team is redoing the same round, so the previous
// attempt isn't worth remembering.
//
// Each row shows the round number, the story (or "Untitled"),
// the vote count, and a compact verdict derived from the same
// `computeVerdict` helper RevealPanel uses for the live round.
// Colour-codes match: green = consensus, neutral = close,
// primary = discuss, muted = empty / meta-only.

import { computed, ref } from "vue"
import type { DeckId } from "./PokerBoard.vue"
import { computeVerdict, type Verdict } from "./verdict"

export type HistoryEntry = {
  round: number
  story: string | null
  deck: DeckId
  cards: string[]
  values: string[]
}

const props = defineProps<{
  history: HistoryEntry[]
}>()

// Map each entry's votes through the shared verdict logic, then
// derive a compact label. The full RevealPanel headlines are too
// long for a single-line row; we squash to one of:
//   "5"       (consensus value)
//   "5 / 8"   (close call range)
//   "discuss" (wide spread)
//   "?" / "☕" (everyone picked the meta card)
//   "—"       (no votes at all)
function compactLabel(v: Verdict): string {
  switch (v.kind) {
    case "consensus":
    case "single":
      return v.value
    case "close":
      return `${v.low} / ${v.high}`
    case "discuss":
      return "discuss"
    case "all_question":
      return "?"
    case "all_coffee":
      return "☕"
    case "none":
      return "—"
  }
}

function labelClass(v: Verdict): string {
  switch (v.kind) {
    case "consensus":
      return "text-success"
    case "discuss":
      return "text-primary"
    case "close":
    case "single":
      return "text-foreground"
    case "all_question":
    case "all_coffee":
    case "none":
      return "text-muted-foreground"
  }
}

// Pre-compute the per-row verdict so the template stays declarative.
const rows = computed(() =>
  props.history.map((entry) => {
    const v = computeVerdict(entry.values, entry.cards)
    return {
      round: entry.round,
      story: entry.story,
      voteCount: entry.values.length,
      label: compactLabel(v),
      cls: labelClass(v),
    }
  }),
)

// ── Copy-to-clipboard export ───────────────────────────────────────
// Build a plain-text snapshot of the session that pastes cleanly
// into Jira / Linear / Notion / Slack — one line per round,
// chronological (oldest-first). The on-screen panel orders rows
// newest-first because that's what scans well; an exported list
// reads better in the order things actually happened.
function exportVerdict(v: Verdict): string {
  switch (v.kind) {
    case "consensus":
    case "single":
      return v.value
    case "close":
      return `${v.low} or ${v.high} (close call)`
    case "discuss":
      return "needs discussion"
    case "all_question":
      return "everyone wants clarification"
    case "all_coffee":
      return "everyone needs a break"
    case "none":
      return "no votes"
  }
}

function buildExport(): string {
  return [...props.history]
    .reverse()
    .map((entry) => {
      const v = computeVerdict(entry.values, entry.cards)
      const story = entry.story || "Untitled"
      return `Round ${entry.round} — ${story} — ${exportVerdict(v)}`
    })
    .join("\n")
}

// Mirrors the fallback logic in `assets/js/app.js`'s CopyToClipboard
// hook — we don't import from there because that's a Phoenix.LiveView
// hook tied to a `data-copy-url` attribute, and this button lives
// inside a Vue island. The browser API needs a secure context
// (HTTPS or localhost); the textarea + execCommand fallback works
// on plain-HTTP LAN test setups.
async function copyToClipboard(text: string): Promise<boolean> {
  if (navigator.clipboard && window.isSecureContext) {
    try {
      await navigator.clipboard.writeText(text)
      return true
    } catch (err) {
      console.warn("clipboard.writeText failed, falling back:", err)
    }
  }
  const ta = document.createElement("textarea")
  ta.value = text
  ta.setAttribute("readonly", "")
  ta.style.position = "fixed"
  ta.style.top = "-1000px"
  ta.style.opacity = "0"
  document.body.appendChild(ta)
  ta.select()
  ta.setSelectionRange(0, text.length)
  let ok = false
  try {
    ok = document.execCommand("copy")
  } catch (err) {
    console.warn("execCommand('copy') threw:", err)
  }
  document.body.removeChild(ta)
  return ok
}

type CopyState = "idle" | "copied" | "failed"
const copyState = ref<CopyState>("idle")
let resetTimer: number | null = null

async function handleCopy() {
  const ok = await copyToClipboard(buildExport())
  copyState.value = ok ? "copied" : "failed"
  if (resetTimer !== null) window.clearTimeout(resetTimer)
  resetTimer = window.setTimeout(() => {
    copyState.value = "idle"
    resetTimer = null
  }, 1500)
}

const copyLabel = computed(() => {
  switch (copyState.value) {
    case "copied":
      return "Copied!"
    case "failed":
      return "Copy failed"
    default:
      return "Copy as text"
  }
})
</script>

<template>
  <details
    v-if="history.length > 0"
    class="rounded-xl border bg-card/60 backdrop-blur-sm group"
  >
    <summary
      class="cursor-pointer list-none px-4 py-3 flex items-center justify-between gap-3 hover:bg-accent/30 transition-colors rounded-xl group-open:rounded-b-none"
    >
      <span class="text-xs uppercase tracking-wider text-muted-foreground font-display">
        Past rounds
      </span>
      <span class="flex items-center gap-2 text-xs text-muted-foreground">
        <span class="tabular-nums">{{ history.length }}</span>
        <!-- Native disclosure caret. Rotates via group-open: utility. -->
        <span
          aria-hidden="true"
          class="transition-transform group-open:rotate-180 select-none"
        >
          ▾
        </span>
      </span>
    </summary>

    <ul class="divide-y border-t">
      <li
        v-for="row in rows"
        :key="row.round"
        class="px-4 py-2 flex items-center gap-3 text-sm"
      >
        <span class="text-xs text-muted-foreground tabular-nums w-10 shrink-0 font-mono">
          R{{ row.round }}
        </span>
        <span
          :class="[
            'flex-1 min-w-0 truncate',
            row.story ? 'text-foreground' : 'text-muted-foreground italic',
          ]"
        >
          {{ row.story || "Untitled" }}
        </span>
        <span
          v-if="row.voteCount > 0"
          class="text-[11px] text-muted-foreground tabular-nums shrink-0"
        >
          {{ row.voteCount }} vote{{ row.voteCount === 1 ? "" : "s" }}
        </span>
        <span :class="['shrink-0 font-mono font-bold tabular-nums', row.cls]">
          {{ row.label }}
        </span>
      </li>
    </ul>

    <!-- Export footer. Sits inside the disclosure so it only takes
         space when the user is already inspecting the history.
         Button label cycles idle → copied (or failed) → idle on a
         1.5s timer for visible feedback without a toast system. -->
    <div class="border-t px-4 py-2 flex items-center justify-between gap-3">
      <span class="text-[11px] text-muted-foreground italic">
        One line per round — pastes cleanly into Jira / Linear / Notion.
      </span>
      <button
        type="button"
        @click="handleCopy"
        :class="[
          'shrink-0 px-3 py-1 text-xs rounded-md border transition-colors cursor-pointer',
          copyState === 'copied'
            ? 'bg-success/10 text-success border-success/30'
            : copyState === 'failed'
              ? 'bg-destructive/10 text-destructive border-destructive/30'
              : 'bg-card hover:bg-accent text-foreground border-input',
        ]"
      >
        {{ copyLabel }}
      </button>
    </div>
  </details>
</template>
