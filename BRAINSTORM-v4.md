# mixchamb v4 — multi-activity direction

The original `BRAINSTORM.md` is framed around music ("real-time
collaborative studio"). This doc captures the pivot, the
decisions locked so far, and the open questions for the next
conversation. Treat it as the planning surface above `BRAINSTORM.md`
until v4 features start landing — then it folds back into the
main doc as another `## Versions` entry.

---

## 1. What changed

mixchamb is no longer music-only. The new framing:

> **A suite of realtime collaborative activities for productivity
> and fun, with optional sequencing.**

Music stays as one activity, alongside future tools targeted at
distributed engineering teams:

- **Planning poker** ✅ — estimate cards, reveal, discuss, re-vote
  _(shipped 2026-05-23; see `features/planning-poker.md`)_
- ~~**Standup**~~ — _dropped (2026-05-27): standups happen live on
  Google Meet / Zoom; an async round-robin version is low value
  (see §7)_
- **Retrospective** ✅ — multi-column board (custom names; default
  Good / Bad / Start / Thanks), optional dot-voting, persisted
  action items _(v1 shipped 2026-05-25; spec at
  `features/retrospective.md`; §11 polish + real-world gaps
  documented in §6a)_
- ~~**Icebreaker**~~ — _dropped (2026-05-27): folded into Mini-game;
  prompts / polls / would-you-rather are just small synchronous games_
- **Mini-game** ✅ _built 2026-05-27_ — small synchronous games
  (Pictionary-style, trivia, Gartic Phone-ish; absorbs the icebreaker
  prompts / polls / would-you-rather idea). Shipped: a game-registry
  framework + two games — Pictionary (live draw-and-guess) and Gartic
  Phone (write→draw→describe chain + album). See
  `features/mini-game.md`.
- **Music** ✅ — the existing chamber experience (carried over from
  v1–v3)

Each activity is a different "room mode" inside the same chamber
shell. Users go to a chamber URL; what they see inside depends on
which activity is currently active there.

## 2. Why the architecture survives the pivot

The core code from v1–v3 (`Chambers.Server` GenServer +
`Phoenix.Presence` + `Phoenix.PubSub` + the `<.vue v-component=…>`
island pattern) is not music-specific. It's *"realtime room with
people in it doing something together"*. Music was instance #1.
Each new activity is instance #N: a new Vue component + a small
event vocabulary on top of the same chamber broadcast.

What stays:
- `Chambers.Server` per-chamber GenServer (state, recent-events
  replay)
- `Phoenix.Presence` for who-is-here
- PubSub broadcast topology
- Anonymous-user identity + alias
- Admin tooling (drain, restart, audit log, presence tracking)

What evolves:
- `chambers.kind` field expands. Today: `"chaos"` / `"secret"` for
  music-only. Tomorrow: also carries the *activity* (`"music"` /
  `"poker"` / `"retro"` / …). Either by reusing `kind` or adding
  a new `activity` field — see open question §5.
- The Vue island in `Chamber.vue` swaps based on
  `chamber.activity`. Existing instrument pads are one branch of
  that swap.

What's music-specific and goes inert in non-music modes:
- The chamber FX bus (reverb / delay / chamber-kind preset). Not
  rendered when activity is non-musical.
- The 7 instrument engine modules in `assets/vue/lib/audio/*.ts`.
  Lazy-loaded, so they don't ship when irrelevant.
- The recording / replay infrastructure. Could be repurposed for
  other activities later (e.g. "replay the retro") but skipped in v4 MVP.

## 3. Decisions locked (2026-05-22)

1. **Tools-first framing**, not event-first. mixchamb is a *suite
   of activities*; sequencing is optional. The wedge against
   single-purpose incumbents (Planning Poker app, Geekbot, Miro
   retro, etc.) is that one platform hosts the whole flow.
2. **First users: a real internal team.** Internal use against
   real ceremonies is the only validation that matters for v4.
   Build for ceremonies the team is already running.
3. **Host-driven room transitions** for the sequencing layer when
   it ships. Schedule-driven and activity-driven transitions
   remain on the table for later.
4. **Same chamber morphs activity; no per-activity chambers.** A
   chamber is a stable URL with continuous presence. Switching
   activity is a state flip inside that chamber, not a redirect.
5. **MVP scope = planning poker.** Music is already shipped.
   Planning poker is the first *new* activity, picked because it
   has the tightest mechanics, well-bounded scope, and the team
   needs it weekly. Standup looked like the runner-up here, but was
   later dropped (see §7) — it's a live video-call ritual, not an
   async chamber activity.
6. **Sequencing requires login** (when it ships, later). Anonymous
   users can run single-activity chambers freely; only authenticated
   users can save event templates / run multi-activity sequences.

## 4. Landing-page model

User journeys after the pivot:

- **Landing (`/`)** — describes mixchamb as the suite, lists
  available activities, lets the user choose one. Each activity
  has its own "create a chamber" or "enter the chaos chamber" CTA.
  Music's existing landing copy + button gets one slot in this
  list, not the whole page.
- **Anonymous create + share** — a user picks "Plan a poker
  session," gets a chamber URL, shares it, others join. Same
  pattern that music already uses.
- **Authenticated event-series** (later) — a logged-in user defines
  a sequence ("music → retro") and runs it; the host
  advances the room between activities; participants follow.

## 5. Architectural decisions (2026-05-22, second pass)

Second round of decisions on top of §3's framing. All seven of the
original open questions are now answered.

1. **Schema change — add a new `chambers.activity` column.**
   *(Corrected from an earlier draft that said this was an
   "Option B" split of `chambers.kind` — `kind` was never a
   visibility field; see §5a below.)* The `activity` column is
   a new string (`"music"` / `"poker"` / future activities) with
   default `"music"` for back-compat. One migration. The
   existing `kind` column is untouched and stays a music-only
   reverb-preset field.

2. **Per-activity visibility — chaos is music-only; every other
   activity is link-only ("secret").** The chaos chamber is a
   music-specific concept (singleton public room; drop in, jam
   with strangers). A public always-on poker chamber doesn't
   make sense — poker happens with named colleagues. Enforce in
   two places:
   - **Create-chamber UI**: only music chambers can be created
     as the chaos chamber (and the chaos chamber already exists
     as a singleton, so in practice every user-created chamber
     is link-only regardless of activity). The activity picker
     for new chambers doesn't expose a "create a chaos poker
     chamber" option.
   - **Activity-switch on the existing chaos chamber is
     blocked**: when a chamber row has `slug = "chaos"` AND
     `creator_user_id IS NULL` (the system-chamber marker),
     the host dropdown is hidden and `Mixchamb.Chambers` rejects
     any attempt to change its activity. Protects walk-in users
     from being dropped into a poker game they didn't sign up
     for.

3. **Host-only dropdown for switching activity.** The MVP
   control is a `<select>` visible only to the chamber creator
   on user-created chambers, listing the available activities.
   The chaos chamber (system row) renders no dropdown — its
   activity is locked to `"music"`. Switching flips
   `chamber.activity` and broadcasts to all participants; their
   Vue island re-renders.

4. **Creator-is-host for MVP.** No multi-host, no role grants,
   no admin override beyond what's already in `/admin`. Matches
   the existing recording-toggle gate.

5. **No music FX bus / volume slider when activity ≠ music.**
   `Chamber.vue` renders those controls only when
   `chamber.activity === "music"`. Avoids confusing UI in a
   poker session.

6. **Anonymous-user identity is unchanged.** The noun-adj-NN
   auto-name + optional alias pattern carries over to all
   activities; ad-hoc team ceremonies work fine without forced
   login. (Login is required only for sequencing, see §7.)

7. **Ephemeral state for planning poker.** Votes live in the
   `Chambers.Server` GenServer for the chamber's lifetime; no
   database persistence. Same pattern as music note events
   pre-recording. Re-opening voting clears prior votes; next-round
   starts fresh.

8. **Login mechanism (when it lands for sequencing): magic
   link + OAuth Google.** Magic link is the low-friction default;
   OAuth Google for engineering audiences that prefer
   single-sign-on. Not in v4 MVP — but pin this now so the
   `users` schema gets shaped correctly the first time it's
   touched (likely needs `email` + a way to track the chosen
   auth method).

## 5a. Schema correction (logged here so the history is honest)

An earlier pass of this doc claimed that `chambers.kind` already
carried the visibility model (`"chaos"` / `"secret"`) and proposed
splitting it into separate `kind` + `activity` columns. That was
wrong. The actual landscape today:

| Concept | Where it lives | Notes |
|---|---|---|
| **Chaos vs link-only** (visibility) | `slug == "chaos"` + `creator_user_id IS NULL` | Convention, no schema field. The Chaos Chamber is a singleton system row; every user-created chamber has an unguessable slug, which is what makes it "secret". |
| **Reverb preset** (audio character) | `chambers.kind` (string) | `vacuum`, `anechoic`, `room`, `live`, `hall`, `cathedral`, `plate`, `spring`, `echo`. Music-only; meaningless for non-music activities. |
| **Activity** *(new in v4)* | `chambers.activity` (string, default `"music"`) | Added by this migration. |

Implication: §5.1 simplifies to *"add the `activity` column;
leave `kind` alone."* The constraint in §5.2 (chaos = music
only) is enforced in application code at the singleton row, not
as a schema-level relationship between `kind` and `activity`.

## 6. v4 MVP scope (planning poker) — shipped 2026-05-23

The 7-step build laid out in the working doc landed end-to-end.
What follows is the durable record of design decisions; the
code under `lib/mixchamb/chambers/poker_session.ex`,
`lib/mixchamb/chambers/server.ex`,
`lib/mixchamb_web/live/chamber_live.ex`, and
`assets/vue/activities/poker/` is the implementation of truth.

### 6.1 Decks

Four decks ship; host picks one at chamber creation and can
switch only while `votes == %{}`:

| Deck (atom) | Values | Numeric stats? |
|---|---|---|
| `:fibonacci` (default) | `1, 2, 3, 5, 8, 13, 21, ?, ☕` | avg + median |
| `:modified_fibonacci` | `0, ½, 1, 2, 3, 5, 8, 13, 20, 40, 100, ?, ☕` | avg + median |
| `:tshirt` | `XS, S, M, L, XL, ?` | mode only |
| `:pow2` | `1, 2, 4, 8, 16, 32, ?, ☕` | avg + median |

Mid-vote deck switches are server-rejected (would orphan
already-cast values).

### 6.2 State machine

Two persistent statuses on `PokerSession.status`: `:voting` and
`:revealed`. The "next round" phase is a transition action, not
a status — it clears votes and increments `round`. "Re-vote"
is a soft reset that clears votes but keeps `round`.

### 6.3 Broadcasts (all on `chamber:<slug>`)

| Event | Payload | Trigger |
|---|---|---|
| `{:poker, :vote_cast, user_id}` | user id only — values stay private until reveal | participant votes (or changes vote) |
| `{:poker, :vote_withdrawn, user_id}` | user id | participant un-picks |
| `{:poker, :revealed, votes}` | `%{user_id => value}` | host clicks reveal |
| `{:poker, :cleared, round, story, deck}` | new round + story + deck | host clicks next-round OR re-vote |
| `{:poker, :story_changed, story}` | new story | host inline-edits the title |
| `{:poker, :deck_changed, deck}` | new deck atom | host switches deck while votes empty |

LV clients receive these and re-pull the authoritative session
via `Chambers.Server.poker_state/1` rather than diffing against
a local copy.

### 6.4 Vote privacy

`PokerSession.votes` holds `%{user_id => value}` on the server.
The LV's `poker_view/2` filters: during `:voting`, only the
caller's own vote value is sent to the browser; other voters
appear as user-ids in `voted_user_ids` only. On `:revealed`,
all values are exposed.

### 6.5 Vue component split

```
assets/vue/activities/poker/
├── PokerBoard.vue        # top-level; composes the 5 below
├── StoryHeader.vue       # inline-editable story + round number
├── CardDeck.vue          # the deck the user picks from
├── ParticipantsRow.vue   # avatars + card silhouettes (flip on reveal)
├── RevealPanel.vue       # distribution + stats
└── HostControls.vue      # reveal / re-vote / next-round / deck dropdown
```

Folder convention mirrors `assets/vue/instruments/`; next
activity goes under `assets/vue/activities/<name>/`.

### 6.6 Edge cases handled

| Case | Handling |
|---|---|
| Late joiner during `:voting` | Can vote; their card joins the tally |
| Late joiner during `:revealed` | Sees the reveal; can't add a vote until next-round |
| Leaver mid-vote | Vote dropped via the LV's existing presence path on disconnect |
| Host leaves | Session freezes for MVP (no host transfer; multi-host comes later) |
| Re-vote with zero votes pre-reveal | No-op |
| Reveal with zero votes | Allowed — empty distribution shown |
| Two votes from same user during `:voting` | Latest value wins; `:vote_cast` re-broadcast |
| Voting attempt during `:revealed` | Rejected at PokerSession layer |

### 6.7 Constraints kept

- **No persistence** beyond chamber lifetime — `PokerSession`
  lives in `Chambers.Server`'s state; dies with the chamber.
- **No login.** Anonymous users only.
- **No sequencing.** One activity per chamber session.
  Activity-switch UI is deferred (see §7).

Final estimate vs reality: planned ~3–4 days, shipped in two
focused sessions across 2026-05-22/23.

## 6a. Activity #2 (retrospective) — v1 shipped 2026-05-25

Same shape as the planning-poker landing: a 7-step build
walked from migrations to Playwright smoke. Durable design
decisions live in `features/retrospective.md`; this section
is the brief BRAINSTORM-level summary so the parent doc stays
coherent across the multi-activity arc.

**Persistence split.** Unlike poker (every artefact ephemeral
in `Chambers.Server`), retro splits durability:
- `retro_sessions`, `retro_columns`, `retro_cards`,
  `retro_action_items` persist to Postgres — the team can run
  many retros in the same chamber and browse archived ones
- the vote map + discussing-card focus live in
  `Mixchamb.Retro.EphemeralState` inside the GenServer, same
  as poker votes. Materialised onto `retro_cards.vote_count`
  when `:voting → :discuss` so the archived record is the
  durable signal.

**Phase machine.** 5 or 6 phases depending on whether voting
is enabled: `:setup → :brainstorm → :reveal →
[(:voting if voting_enabled) →] :discuss → :archived`. Voting
is opt-in (default off — most retros don't have enough cards
to need it; the host gets a 15-card threshold hint when it
starts mattering).

**Visibility model.** Default: cards hidden from non-authors
during `:brainstorm`, revealed together at `:reveal`. Closed-
card placeholders (one per others' hidden card, coloured by
the column accent) signal that others are contributing
without leaking content. Opt-in `brainstorm_visible` mode
shows all cards live for smaller / higher-trust teams.

**Columns.** Fixed at 4, custom-named per session (default
Good / Bad / Start / Thanks), each lane tinted with one of
the activity-accent tokens for at-a-glance orientation.

**What landed beyond the spec's locked sections** (during the
build pass, after seeing it run):
- Per-column accent tinting + colour-matched closed-card backs
- 15-card threshold hint nudging voting-enable
- `brainstorm_visible` toggle (spec §4 originally rejected,
  reversed during build)
- Empty-session archive warning
- Late-joiner / refresh hydration via `seed_retro_ephemeral/3`
- Bug fix for "can't start a new retro after archive" — the
  GenServer was keeping a stale archived EphemeralState

**Constraints kept:** ephemeral votes (no per-user history),
4 fixed columns (no add/remove in v1), anonymous-user identity
unchanged, no event sequencing yet.

**Spec-locked gaps — all closed before flipping to ✅:**

1. ✅ **§6 — Action items nested under source cards.** Tied
   actions render under their card in `RetroCard` during
   `:discuss` / `:archived`; freeform actions live in
   `RetroDiscussPanel`. Shared `RetroActionRow` keeps the
   display + inline-edit UI consistent across both contexts.
2. ✅ **§6 — Assignee autocomplete from presence.** Chamber
   participants' alias_or_name strings provided via Vue
   provide/inject from `RetroBoard`; assignee inputs reference
   a `<datalist>` so the browser handles the typeahead. Works
   for both the add form and inline edits, without enforcing
   that the assignee is actually in the chamber.
3. ✅ **§3 — Two-piece author display.** New
   `author_display_name` column on `retro_cards` snapshots
   `user.display_name` separately; cards render
   `alias · display_name` when both exist and differ, just the
   alias when they match (anonymous user without explicit
   alias), just the alias when display_name is null (legacy
   cards predating the column).

**§11 polish backlog (spec-deferred — not required for v1):**

- Card grouping / merging at `:reveal`
- Discussing-card highlight animation (static ring is in;
  animation deferred)
- Action item carry-over from previous retro
- Anonymous mode
- Preset column templates (SSC / MSG / 4Ls)
- Keyboard shortcuts (1–4 add to column, Enter submits, etc.)

**Real-world gaps surfaced by use (not in spec) — all closed:**

- ✅ **Click-to-view archived content.** Each past-retros entry
  links to its read-only permalink at `/archives/retros/:id`
  (`RetroLive` renders the full board).
- ✅ **Edit-mode char counter.** The three edit textareas (card,
  action item, comment) now show a live `n/280` counter,
  matching the add forms.
- ✅ **Vote-cast cue.** Casting a vote plays a soft one-shot blip
  (`playVoteBlip` in `lib/audio.ts`, mirroring poker's
  `playReveal`); silent on withdraw, local-only.
- ✅ **Vote-withdraw hint.** The voting panel shows "Tap a vote
  chip again to withdraw and re-spend", and the vote button's
  `aria-label` toggles Vote / Withdraw.

Final estimate vs reality: planned ~6 working days, shipped in
three focused sessions (v1, a close-the-gaps pass after audit
surfaced the three locked-section misses, then a third pass
closing the four real-world gaps above). The §11 polish items
remain a deliberate v2 backlog — they don't block the ✅ since
the spec explicitly defers polish.

---

## 7. Path forward

1. ✅ **Activity #2 — retrospective.** Shipped 2026-05-25
   (initial pass + close-the-spec-gaps pass after audit). Picked
   novelty over frequency: poker covered the "structured
   ceremony with discrete votes" pattern; retro covers
   "free-form brainstorm → cluster → discuss → action items,"
   which exercises the same architecture differently (persistent
   cards + actions vs. ephemeral poker votes) and surfaced what's
   load-bearing in the shared shell. Spec at
   `features/retrospective.md`.
2. **Add auth — magic link + OAuth Google.** Magic link is the
   low-friction default for the casual case; OAuth Google gives
   the team SSO. Either path lands on a real `users` row with
   `email`. The existing `anonymous_users` table stays as-is —
   the two identities co-exist (logged-in users still get a
   chamber-side display_name + alias; the difference is they can
   own event templates).
3. **Add sequencing.** Logged-in user defines an "event template"
   (`music → retro`); host runs it from a chamber and
   the "advance" button moves the room through the template
   (host-driven transitions, per §3.3). Schedule-driven and
   activity-driven transitions remain on the table for later.
4. **Add more activities** at whatever cadence feels right.
   Each one extends the same `chamber.activity` switch pattern.
   Mini-game (which absorbs the icebreaker idea) ✅ **shipped
   2026-05-27** — `features/mini-game.md`: a game-registry framework
   with **Pictionary** (live draw-and-guess) and **Gartic Phone**
   (write→draw→describe chain + album) as its first two games. A
   third (trivia, lightweight polls) is just a module + Vue stage +
   registry entry — no framework change.

**Dropped from the roadmap (2026-05-27):**

- **Standup.** A round-robin "yesterday / today / blockers"
  ceremony just duplicates what teams already do live on Google
  Meet / Zoom — it's a video-call ritual, not something people
  want to run async in a chamber. Low value for the build cost.
- **Icebreaker.** Folded into Mini-game: prompts, polls, and
  would-you-rather are small synchronous games, so a separate
  activity would only fragment the same idea.

## 8. What this means for the existing music build

- **Nothing breaks.** Music chambers keep working exactly as they
  do today. They just become `activity = "music"` chambers; the
  default activity is `"music"` for back-compat.
- **The `/` landing page** changes to introduce the suite. The
  existing "Enter the chaos chamber" CTA stays but as one of
  several activity entry points.
- **Brand alignment.** "mixchamb" reads as *mix of activities in
  chambers*, which is now literally what the product is. No
  rename needed; the rename to mixchamb in this session was the
  right call regardless of v4.
