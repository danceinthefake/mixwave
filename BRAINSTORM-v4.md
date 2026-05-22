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

- **Planning poker** — estimate cards, reveal, discuss, re-vote
- **Standup** — round-robin updates, optional "yesterday / today /
  blockers" structure, history
- **Retrospective** — multi-column board (start / stop / continue
  or similar), grouping, voting, action items
- **Icebreaker** — prompts, polls, would-you-rather, etc.
- **Mini-game** — small synchronous games (Pictionary-style, trivia,
  Gartic Phone-ish)
- **Music** — the existing chamber experience

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
  `"poker"` / `"standup"` / …). Either by reusing `kind` or adding
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
   needs it weekly. Standup is more frequent but fiddlier on UX —
   ships second.
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
  a sequence ("standup → music → retro") and runs it; the host
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

## 6. v4 MVP scope (planning poker)

Smallest thing that earns "we used it in real sprint planning":

- **Schema migration** — add `activity` column to `chambers`
  (string, default `"music"`, enum-ish: `"music"` / `"poker"`).
  `kind` (the reverb preset) is left alone; it stays a
  music-only field.
- **Create-chamber form** — activity picker first. The chaos
  chamber is a pre-seeded singleton (no UI creates one), so
  every user-created chamber is link-only by default; activity
  picker just chooses `"music"` or `"poker"`. Server-side
  validates that activity-switch on the singleton chaos chamber
  is rejected.
- **Chamber.vue routing** — branch on `chamber.activity`: render
  existing instrument shell when `"music"`, render new
  `PokerBoard.vue` when `"poker"`. Music FX bus / volume slider
  / instrument dock only mount when activity is `"music"`.
- **`PokerBoard.vue`** — three states:
  - **Voting** — each participant sees the card deck (Fibonacci-ish:
    `1, 2, 3, 5, 8, 13, 21, ?, ☕`), picks a card, sees a "voted"
    indicator next to other participants' names without seeing
    their values.
  - **Reveal** — host clicks "reveal," everyone's cards turn face
    up simultaneously, distribution chart, average/median.
  - **Re-vote / next** — host can re-open voting (resets) or start
    next ticket.
- **Host controls** — visible only to the chamber creator: deal /
  reveal / clear / next-round buttons, plus a "switch activity"
  dropdown. The chaos chamber (singleton system row,
  `creator_user_id IS NULL`) has no host and no dropdown — it's
  music-locked. Every user-created chamber's host sees the full
  set: `music` ↔ `poker`.
- **No persistence** beyond chamber lifetime. Votes live in
  `Chambers.Server`'s state; cleared on re-vote or chamber close.
  No ticket history, no Jira integration.
- **No login.** Anonymous users only; the existing
  noun-adj-NN identity carries straight over.
- **No sequencing.** One activity per chamber session for now.

Estimated build: ~3–5 days end-to-end for someone who knows the
codebase. Vue island shape mirrors the existing instrument-pad
pattern, so a lot of structure is copy-with-edits.

## 7. Path forward

After the planning-poker MVP lands and gets used in real
sprint planning at least twice:

1. **Pick activity #2.** Probably standup or retro. Standup wins
   on frequency (daily), retro wins on novelty. User signal from
   the team should decide.
2. **Add auth — magic link + OAuth Google.** Magic link is the
   low-friction default for the casual case; OAuth Google gives
   the team SSO. Either path lands on a real `users` row with
   `email`. The existing `anonymous_users` table stays as-is —
   the two identities co-exist (logged-in users still get a
   chamber-side display_name + alias; the difference is they can
   own event templates).
3. **Add sequencing.** Logged-in user defines an "event template"
   (`standup → music → retro`); host runs it from a chamber and
   the "advance" button moves the room through the template
   (host-driven transitions, per §3.3). Schedule-driven and
   activity-driven transitions remain on the table for later.
4. **Add activity #3, #4, #5** at whatever cadence feels right.
   Each one extends the same `chamber.activity` switch pattern.

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
