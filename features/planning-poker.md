# Planning poker — feature spec

Shipped 2026-05-23 as the second activity in a mixchamb chamber
(the first is music). This doc is the per-section reference for
what planning poker is, how it behaves, and which decisions are
locked. The architectural framing — why activity is a column on
`chambers` rather than its own row, how chaos-vs-secret stayed a
convention, the creator-is-host MVP scope — lives in
`../BRAINSTORM-v4.md` §§3 + 5 + 6.

Code map: `lib/mixchamb/chambers/poker_session.ex`,
`lib/mixchamb/chambers/server.ex` (poker_* casts),
`lib/mixchamb_web/live/chamber_live.ex` (poker_* events +
broadcasts), `assets/vue/activities/poker/` (6-file Vue split).

All sections below are **Locked**.

---

## 1. Session state machine — _Locked_

**Decision:** Three logical states — `voting` → `revealed` →
(next round transition) → `voting`. The persistent
`PokerSession.status` field carries two values: `:voting` and
`:revealed`. The third "next round" phase is the *transition
action* that clears state and returns to `:voting`, not a
status of its own.

Discussion happens naturally between reveal and the host's
"next round" click — no explicit `:discussing` state needed.
If the team reports confusion in practice, it can be added
later as a v4.1+ refinement.

## 2. What is the host voting on? — _Locked_

**Decision:** Single story field. One editable single-line field
at the top of the board, editable by the host at any time during
a round. `nil` story falls back to displaying "Round N" only.

~~A pre-loaded story queue is real planning-tool territory and
remains a v4.1+ feature, not MVP.~~ Shipped as a polish iteration
— see the "Pre-loaded story queue" entry below. The single-story
field stays the live source of truth; the queue is just a
backlog the host preloads and `next_round/2` drains.

## 3. Card deck — _Locked_

**Decision:** Ship all four decks; host picks one per chamber.
Default is Fibonacci-ish (most recognisable starting point).
Host can switch decks during the session *only when no votes
are cast* — i.e. at chamber creation, immediately after a
"next round" clear, or any time `votes` is empty. Mid-vote
deck-switching is rejected to avoid lost / orphan votes.

**Decks:**

| Deck (atom) | Values | Numeric avg? |
|---|---|---|
| `:fibonacci` (default) | `1, 2, 3, 5, 8, 13, 21, ?, ☕` | yes |
| `:modified_fibonacci` | `0, ½, 1, 2, 3, 5, 8, 13, 20, 40, 100, ?, ☕` | yes |
| `:tshirt` | `XS, S, M, L, XL, ?` | no |
| `:pow2` | `1, 2, 4, 8, 16, 32, ?, ☕` | yes |

**UI implications:**

- The chamber-create form has a deck selector (only visible when
  activity = poker).
- `HostControls.vue` carries a deck dropdown, disabled when
  `votes` is non-empty. A small "Lock deck before votes start"
  hint can appear when disabled.
- `RevealPanel.vue` computes avg / median only for numeric
  decks (Fibonacci, modified Fibonacci, pow2); the t-shirt
  reveal shows mode + distribution only.

**Server validation:** `Chambers.Server` rejects a
`{:set_deck, deck}` message unless `votes == %{}`. Client UI
should mirror that gate, but the server is authoritative.

## 4. Server-side state shape — _Locked_

**Decision:** the struct below carries every per-session
artefact. Lives inside `Chambers.Server`'s state alongside the
existing music event buffer. `nil` when `chamber.activity !=
"poker"`. Cleared when activity flips away from poker.

```elixir
defmodule Mixchamb.Chambers.PokerSession do
  defstruct status: :voting,        # :voting | :revealed
            deck: :fibonacci,       # :fibonacci | :modified_fibonacci
                                    # | :tshirt | :pow2 — host-selectable,
                                    # only mutable while votes == %{}
            story: nil,             # editable string, nil = "Round N"
            votes: %{},             # %{user_id => card_value (string)}
            round: 1                # increments on clear / next
end
```

The struct lives inside `Chambers.Server`'s state alongside the
existing music event buffer. It's `nil` when `chamber.activity
!= "poker"` and gets cleared when activity flips away from poker
(§5 of `../BRAINSTORM-v4.md` already requires music FX bus to
unmount under the same flip — same pattern).

PubSub broadcasts on the existing `chamber:<slug>` topic:

| Event | Payload | Trigger |
|---|---|---|
| `{:poker, :vote_cast, user_id}` | just the user id, no value | participant votes (or changes vote while open) |
| `{:poker, :vote_withdrawn, user_id}` | user id | participant un-picks a card |
| `{:poker, :revealed, votes}` | full `%{user_id => value}` map | host clicks "reveal" |
| `{:poker, :cleared, round, story, deck}` | new round number + new story text + current deck | host clicks "next round" |
| `{:poker, :story_changed, story}` | new story text | host edits the title inline |
| `{:poker, :deck_changed, deck}` | new deck atom | host switches deck while `votes == %{}` |

**Why values are strings:** because `?` and `☕` aren't numbers.
Numeric stats (average, median) computed client-side after
filtering out non-numeric cards.

**Persistence:** none. State dies with the chamber. Matches the
v4 §3.7 ephemeral decision.

## 5. "Voted" indicator UX — _Locked_

**Decision:** Card silhouette. A face-down card icon appears
next to each participant who has voted; on reveal, the icon
flips to show the value.

Uses the deck's own visual language, makes the reveal feel like
a card flip (satisfying animation hook), and is unambiguous
about state. The card silhouette implementation lives in
`ParticipantsRow.vue`; the flip transition is a CSS
`transform: rotateY()` on reveal.

## 6. Edge cases — _Locked_

| Case | Handling |
|---|---|
| **Late joiner during `:voting`** | They can vote; their card joins the tally. |
| **Late joiner during `:revealed`** | They see the reveal but can't add a vote (round is closed). The next-round broadcast catches them up if/when it fires. |
| **Leaver mid-vote** | Their vote is dropped from the tally on `Presence` leave. The "voted" silhouette next to their name disappears with them. |
| **Host leaves** | The chamber stays running; any **co-host** the creator promoted before leaving can keep driving (reveal / advance / set queue / switch activity). With no co-hosts promoted, the session freezes until the creator returns — multi-host is opt-in, not automatic transfer. See "Multi-host" in the polish iterations below. |
| **Switch activity mid-session (poker → music)** | `PokerSession` state is cleared. Switching back recreates a fresh session at round 1. No persistence across switches. |
| **Switch activity mid-music (music → poker)** | Existing music chamber state is left alone (just hidden); poker session initialises fresh. |
| **Two votes from the same user (changes mind)** | Allowed during `:voting`. Latest value wins; broadcast `vote_cast` again. Disallowed during `:revealed`. |
| **Host clicks "reveal" with zero votes cast** | Reveal anyway; show empty distribution. (Don't gate on "≥1 vote required" — adds rule complexity for no win.) |

## 7. Vue component split — _Locked_

**Decision:** Six-file split under `assets/vue/activities/poker/`.

```
assets/vue/activities/poker/
├── PokerBoard.vue        # top-level mounted when chamber.activity = "poker"
├── StoryHeader.vue       # editable story title + round number
├── CardDeck.vue          # the deck (9-13 cards depending on selected deck) the user picks from
├── ParticipantsRow.vue   # avatars + voted-status silhouettes + revealed values
├── RevealPanel.vue       # distribution + avg / median (numeric decks) or mode (t-shirt deck)
└── HostControls.vue      # reveal / re-vote / next-round / story-edit / deck dropdown
```

The folder convention mirrors `assets/vue/instruments/` for the
seven existing instrument pads. When standup / retro /
icebreaker land, each gets its own `activities/<name>/` sub-folder.

The five-sub-component split (vs. one big file) keeps each region
~under 100 lines of HEEx + logic, testable in isolation, and
matches the established pattern.

## Ready-to-build checklist

All seven sections locked as of 2026-05-22. The implementation
order I'd recommend:

1. ✅ **Migration** — add `activity` string column to `chambers`,
   default `"music"`. (10 min.)
2. ✅ **`PokerSession` struct + `Chambers.Server` integration** —
   handle the new messages (`:vote`, `:reveal`, `:next_round`,
   `:set_story`, `:set_deck`) and broadcast the six events.
   (Half-day.)
3. ✅ **Create-chamber form** — activity picker, deck picker
   (visible only when activity = poker). Every user-created
   chamber is link-only by default; the chaos chamber is a
   pre-seeded singleton and never created through this form.
   (~2 hours.)
4. ✅ **`Chamber.vue` activity-branching** — render existing
   instrument shell when `"music"`, render `<PokerBoard>` when
   `"poker"`; hide music FX bus / volume slider in non-music.
   (~1 hour.)
5. ✅ **`PokerBoard.vue` + 5 sub-components** — six files. The
   tightest bottleneck of the build. (~1.5 days for a polished
   first pass.)
6. ✅ **Host controls + deck dropdown gating** — reveal / re-vote
   / next-round / inline story edit / deck dropdown
   (disabled when `votes != %{}`). (Half-day.)
7. ✅ **Smoke test** — open three browsers, vote, reveal, re-vote,
   switch decks between rounds, switch activity to music and
   back. Confirm presence and state behave as specified.
   (Few hours.)

   Status: 3-browser Playwright smoke test passes end-to-end —
   vote, reveal (avg/median/mode for numeric decks, mode-only
   for t-shirt), re-vote (Round 1 preserved), next-round
   (advances), deck switch (gated when votes exist on host,
   non-hosts have no dropdown at all). Activity-switching UI is
   shipped too: chamber_live.ex renders a host-only Activity
   chip-strip; clicking flips `chamber.activity` via
   `Chambers.set_activity/2`, broadcasts `:activity_changed`,
   every client reloads its poker_session (fresh on poker, nil
   on music). Confirmed via 2-browser Playwright smoke
   (host + observer): music ↔ poker round-trip with PokerBoard
   mount/unmount on both clients, instrument dock hidden under
   poker, no console errors.

Total estimate: **~3-4 working days**.

---

## Polish iterations (post-v4 ship)

After the locked sections above shipped, a polish pass added the
following. Each is small enough to track as a bullet rather than
its own locked section; documented here so future work can see
what's in beyond the MVP without trawling git log.

- **Consensus headline on reveal.** RevealPanel renders a
  one-glance verdict above the distribution bars: `Consensus: X`
  (green / `text-success`), `Close call — X or Y` (foreground,
  for adjacent values in the deck order), `Wide range — discuss`
  (primary pink, for wider spreads). `?` and `☕` are stripped
  from the spread check — they're meta-votes, not grades — but
  surface in their own headlines when everyone picks them
  (`Everyone wants clarification` / `Time for a break ☕`).
  Verdict logic lives in `assets/vue/activities/poker/verdict.ts`
  and is shared with the history panel below.

- **Reveal moment.** The host's Reveal click no longer flips
  cards instantly. PokerBoard.vue lags `flipped` behind
  `status === "revealed"` by 800 ms; during the gap, an
  ascending C5–E5–G5–C6 arpeggio plays via `playReveal()` in
  `assets/vue/lib/audio.ts`, last note timed with the flip.
  RevealPanel fades in 100 ms behind the cards (`<Transition>`
  wrapper in PokerBoard.vue) so the verdict lands with the
  flip rather than racing it. `prefers-reduced-motion` drops
  the suspense — audio isn't motion, so the chime still plays.
  Late joiners and post-reload mounts skip the suspense (they
  missed the chime; flipping their cards instantly is the right
  call).

- **Round history panel.** `PokerSession.history` field, pushed
  by `next_round/2` whenever the closing round had at least one
  vote or a non-nil story. Re-vote does **not** push (the team
  is redoing the same round). Each entry snapshots
  `{round, story, deck, votes}` and prepends — newest-first.
  `poker_view` shapes entries for the wire as
  `{round, story, deck, cards, values}`, stripping user_ids
  (history shows verdicts only, not per-user breakdowns) and
  including each entry's deck-card-order snapshot so the
  "close" verdict computes correctly even when the deck was
  switched between rounds. Rendered as a collapsed `<details>`
  disclosure below HostControls in `RoundHistory.vue`.

- **Copy-as-text export.** Footer button inside the Past-rounds
  disclosure builds a plain-text snapshot — one line per round,
  oldest-first, format `Round N — Story — verdict` — and copies
  to the clipboard. Verdict format expands slightly for export
  (`5 or 8 (close call)` / `needs discussion`) since paste-
  context isn't competing for row space. Clipboard helper is
  inlined in `RoundHistory.vue` rather than reusing the LV-side
  `CopyToClipboard` hook, which is tied to a `data-copy-url`
  attribute and lives in Phoenix's DOM tree (this button sits in
  a Vue island). Same secure-context preference + textarea
  fallback in ~25 lines.

- **"Waiting on …" nudge.** Once at least one vote is in,
  ParticipantsRow shows a small italic hint above the silhouettes
  listing whoever's left. Up to three names
  (`Waiting on Alice, Beto, and Citra`); past that, switches to
  a count (`Waiting on 4 players`). Self renders as `you` so the
  laggard realises the room's waiting on them specifically —
  otherwise their own alias would appear and read like a stranger
  in the third person. Non-voter silhouettes that were already
  `.is-empty` drop opacity 0.7 → 0.4 once someone else has voted
  (`.is-overdue` modifier in `ParticipantsRow.vue`'s scoped CSS),
  with a 200 ms fade so the dim arrives in step with the hint.

- **Audio gate covers poker too.** `Chamber.vue`'s gate used to be
  `activity === "music"` only, leaving a non-host who joined a
  poker chamber and never voted before the host hit Reveal with
  no chime — their AudioContext never got the gesture. Now the
  gate renders for any activity; heading branches via a
  `gateHeading` computed: `Tap to start jamming` for music,
  `Tap to take a seat` for poker. Sub-line and button label are
  activity-neutral. `audioReady` is per-mount, so dismissing the
  gate once covers the chamber's lifetime regardless of activity
  switches.

- **Keyboard shortcuts.** PokerBoard registers a window keydown
  listener (AbortController-cleaned on unmount, mirrors
  `useInstrumentKeyboard`'s shape): `1`–`9` vote the card at
  that deck index (during `:voting` only); `Esc` withdraws an
  active vote; `R` reveals (host only, during `:voting`); `N`
  advances to next round (host only, during `:revealed`); `E`
  re-votes (host only, during `:revealed`). Skips fire when
  typing in the story editor or alias input (via
  `isTypingInForm` from `lib/utils`), when any modifier key is
  held (don't steal browser shortcuts), and on auto-repeat
  (no rapid-fire votes from a stuck key). `<kbd>` chips in
  CardDeck (per card, sm+ viewports) and HostControls
  (`R`/`N`/`E` inside each action button) handle discoverability.

- **Activity-switching UI.** The §7 status note used to claim
  the matrix entries for cross-activity switching were deferred.
  In fact `chamber_live.ex` already renders a host-only Activity
  chip-strip that flips `chamber.activity` via
  `Chambers.set_activity/2`, broadcasts `:activity_changed`, and
  every client reloads its `poker_session` (fresh on poker, nil
  on music). Confirmed via 2-browser Playwright smoke. §7 above
  is updated.

- **Multi-host (co-host promotion).** Section §6's "host privilege
  does not transfer" rule is loosened: the creator can promote any
  participant to a co-host who then gets every host-only action
  (reveal / next round / set queue / set deck / set activity /
  set kind / record). Hosts live in `Chambers.Server`'s ephemeral
  state — a `MapSet` seeded with the creator's id at init, mutated
  via two new casts (`:promote_host`, `:demote_host`) that
  authorise against the creator id on the server side (LV check
  is fast-path only). `:hosts_changed` broadcasts re-flow the
  set to every client; `chamber_live.ex` recomputes `@is_host`
  from `MapSet.member?(@hosts, current_user.id)` so the entire
  host-gated UI flips in one diff. Creator can't be demoted, even
  by themselves (chamber-anchor invariant); co-hosts can
  self-demote ("Step down as host") but can't promote anyone
  else (no daisy-chain). State dies with the chamber, same as
  poker + music — consistent with v4 §3.7. Two new badges in the
  presence aside (`Creator` pink, `Host` cyan) plus inline
  promote/demote links per row.

- **Pre-loaded story queue.** `PokerSession.queue: [String.t()]`
  holds a backlog the host loads via a textarea in HostControls
  (one story per line). `next_round/2` consumes the queue head
  into `:story` when no explicit `:story` opt was passed, so the
  free-form workflow still wins on inline edits — paste a
  backlog, let it auto-drain; edit the title inline to override
  for one round, queue stays untouched. New cast
  `:poker_set_queue` + broadcast `{:poker, :queue_changed, _}`
  replace the queue server-side (no append mode; pre-fill the
  textarea with the current queue and edit to add/remove).
  PokerSession trims blanks and caps at 50 lines so a stray
  giant paste can't bloat ephemeral state. StoryHeader renders
  an "Up next: X · N more queued" preview visible to everyone
  (non-hosts benefit from seeing the pace); the textarea editor
  is host-only inside HostControls. Section §2 above is updated
  — the queue moved from "v4.1+ deferred" to "shipped".
