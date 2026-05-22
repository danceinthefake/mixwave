# Planning-poker MVP — implementation details

Working surface for the implementation-level decisions on the
v4 planning-poker MVP. The strategic decisions (schema split,
visibility constraint, creator-is-host, ephemeral state, etc.)
are locked in `../BRAINSTORM-v4.md` §§3 + 5. This doc covers the
"decide while building" details listed at the end of v4's §6.

**Status legend per section:** _Pending_ (proposed, awaiting
sign-off), _Locked_ (decided; ready to code against).

Once every section is _Locked_, fold the resolutions into
`../BRAINSTORM-v4.md` §6 and delete this doc.

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

A pre-loaded story queue is real planning-tool territory and
remains a v4.1+ feature, not MVP.

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
| **Host leaves** | For MVP, session freezes. Host privilege does not transfer to anyone else. New chamber needed if creator never returns. (Multi-host comes later.) |
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

1. **Migration** — add `activity` string column to `chambers`,
   default `"music"`. (10 min.)
2. **`PokerSession` struct + `Chambers.Server` integration** —
   handle the new messages (`:vote`, `:reveal`, `:next_round`,
   `:set_story`, `:set_deck`) and broadcast the six events.
   (Half-day.)
3. **Create-chamber form** — activity picker, deck picker
   (visible only when activity = poker). Every user-created
   chamber is link-only by default; the chaos chamber is a
   pre-seeded singleton and never created through this form.
   (~2 hours.)
4. **`Chamber.vue` activity-branching** — render existing
   instrument shell when `"music"`, render `<PokerBoard>` when
   `"poker"`; hide music FX bus / volume slider in non-music.
   (~1 hour.)
5. **`PokerBoard.vue` + 5 sub-components** — six files. The
   tightest bottleneck of the build. (~1.5 days for a polished
   first pass.)
6. **Host controls + deck dropdown gating** — reveal / re-vote
   / next-round / inline story edit / deck dropdown
   (disabled when `votes != %{}`). (Half-day.)
7. **Smoke test** — open three browsers, vote, reveal, re-vote,
   switch decks between rounds, switch activity to music and
   back. Confirm presence and state behave as specified.
   (Few hours.)

Total estimate: **~3-4 working days**.
