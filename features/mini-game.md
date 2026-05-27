# Mini-game — feature spec

Planned as the next activity in a mixchamb chamber (after music,
planning poker, and retrospective). Unlike those three, mini-game
is a **framework**, not a single ceremony: `chamber.activity =
"minigame"` hosts a *registry* of small synchronous games, and a
session picks which one to play. v1 ships the framework plus **one**
game — **Pictionary** (live draw-and-guess) — and the framework is
shaped so a second game is a new module + Vue component, never a new
activity. The dropped "icebreaker" idea (prompts / polls /
would-you-rather, see `../BRAINSTORM-v4.md` §1 ideas list) lands here
as future lightweight games in the same registry.

The architectural framing — why activity is a column on `chambers`,
the same-shell-different-component pattern, the ephemeral-state-in-
`Chambers.Server` convention — lives in `../BRAINSTORM-v4.md` §§3 + 5
+ 6 and was proven by planning poker (`./planning-poker.md`) and
retrospective (`./retrospective.md`).

**Why the "heaviest option" is tractable:** a live drawing canvas
looks like a brand-new real-time primitive, but the chamber already
fans out high-frequency real-time events — the **music** activity
streams note events over the same `chamber:<slug>` PubSub topic with
a server-side event buffer in `Chambers.Server`. Drawing strokes are
the same shape of problem (many small ordered events, late-joiner
snapshot, one emitter many viewers) and reuse that proven transport.
The novelty is throttling/batching strokes and a per-user view
(the drawer sees the secret word; guessers don't), not the fan-out.

Code map (planned):
- `lib/mixchamb/minigame/game.ex` — the game behaviour (callbacks
  every registry game implements)
- `lib/mixchamb/minigame/registry.ex` — atom → game-module lookup
- `lib/mixchamb/minigame/pictionary.ex` — the v1 game
- `lib/mixchamb/minigame/word_packs.ex` — preset word lists
- `lib/mixchamb/minigame/state.ex` — `MiniGameState` ephemeral struct
- `lib/mixchamb/chambers/server.ex` (`minigame_*` casts + the stroke
  relay)
- `lib/mixchamb_web/live/chamber_live.ex` (`minigame_*` events +
  broadcasts)
- `assets/vue/activities/minigame/` (component split per §8)

Status: **Built + Locked** (2026-05-27). The design below was approved
and implemented in full — framework + Pictionary v1, including the §7
edge cases. Sections are tagged _Locked_; the "Ready-to-build
checklist" at the end tracks what shipped, and §9 marks which polish
items landed vs stayed deferred.

---

## 1. The framework — game registry & session lifecycle — _Locked_

**Decision:** A minigame session is a thin shell around one game
drawn from a registry. The framework owns: the **lobby** (game
picker + player roster + per-game config), the **scoreboard**, and
the **host controls** (start / next / end / play-again). Everything
game-specific (phase rules, what a "turn" means, scoring) is
delegated to the chosen game module via a behaviour.

**Game behaviour** (`Mixchamb.MiniGame.Game`):

```elixir
@callback init(opts :: map) :: state :: map
# Apply a player/host action; return new state + the broadcasts to fan out.
@callback handle_action(state, action :: map, ctx :: map) ::
            {:ok, state, [broadcast]} | {:error, reason}
# Per-user wire payload. Lets the drawer see the secret word while
# guessers see only blanks — same "wire carries more than the UI
# shows" split as poker/retro vote events, but here it's per-recipient.
@callback view(state, user_id :: String.t() | nil) :: map
# Advance the turn/round clock (timer expiry, "next" button).
@callback advance(state, ctx) :: {:ok, state, [broadcast]}
```

**Registry** (v1): `%{pictionary: Mixchamb.MiniGame.Pictionary}`.
Adding a game = one new module implementing the behaviour + one Vue
stage component (§8) + one registry entry. No migration, no new
activity, no `chamber_live.ex` plumbing beyond the existing
`minigame_*` events.

**Session lifecycle (framework-level):**
```
:lobby → (game's own phases) → :gameover
   Start game                     Play again → :lobby  /  End → chamber idle
```

| Framework phase | What's happening | Who can do what |
|---|---|---|
| `:lobby` | Host picks the game from the registry, sets per-game config (Pictionary: word pack, turn timer, round count), sees the player roster. | Host picks game + config + Start. Participants join, set alias, wait. Anyone present at Start is a player. |
| _(game phases)_ | Delegated to the chosen game module (§2 for Pictionary). | Per game. |
| `:gameover` | Final scoreboard. | Host can **Play again** (back to `:lobby`, scores reset) or **End** (session idle; chamber stays, board shows "No game running"). |

**Why a framework over one activity per game:** the brainstorm
framing (`../BRAINSTORM-v4.md` §1) lists Pictionary, Gartic Phone,
trivia, and the absorbed icebreaker polls as one bucket. They share
the lobby / roster / scoreboard / host-control scaffolding and differ
only in the middle. One activity + a registry means the second game
costs a module, not a re-plumb.

**Why "anyone present at Start is a player":** keeps the lobby
simple — no ready-check or join/leave-the-game sub-state. Late
joiners become spectators for the current game and players on the
next (§7).

## 2. Pictionary game flow — phase machine — _Locked_

**Decision:** Turn-based. One **drawer** per turn draws a secret
word on a shared canvas; everyone else races to guess it via text
before the timer runs out. A **round** = every player has drawn
once. A **game** = `round_count` rounds (host config, default 2).

```
:lobby → :turn → :turn_reveal → (next turn) → … → :gameover
 Start    drawing+guessing  word shown,        last turn of
          (timed)           points tallied     last round
```

| Phase | What's happening | Who can do what |
|---|---|---|
| `:turn` | The drawer (assigned a secret word) draws; the timer counts down. Everyone else guesses via a text feed. | **Drawer:** draw / undo / clear; cannot guess. **Guessers:** submit guesses; correct guess locks them out of further guessing this turn. **Host:** skip turn. |
| `:turn_reveal` | The word is shown to all; per-turn points are tallied into the scoreboard; the canvas freezes. | Everyone reads the result. Host advances to the next turn (or auto-advances after a short delay). |
| `:gameover` | Final scoreboard after the last turn of the last round. | Host: Play again / End (§1). |

**Turn order:** players draw in a fixed rotation seeded at Start
(roster order). The rotation is captured once so late joiners /
leavers don't reshuffle who's drawn (§7). A round increments when
the rotation wraps.

**Timer:** per-turn countdown, host-configurable in `:lobby`
(default **80s**; options 60 / 80 / 120). The turn ends early if
**every** non-drawer has guessed correctly. On expiry the phase
auto-advances to `:turn_reveal`.

**Why turn-based single-drawer (Pictionary) and not Gartic Phone
first:** a single shared live canvas with one emitter and many
viewers is the most tractable first drawing game — it's the music
note-streaming shape exactly. Gartic Phone has everyone drawing
their *own* private canvas in a telephone chain, then a synchronized
album reveal — a distinct flow (private per-player surfaces +
chain bookkeeping + album playback). It's the framework's natural
second game (§9), reusing the §3 canvas primitive but a different
session shape.

## 3. The drawing surface — real-time stroke streaming — _Locked_

This is the one genuinely new primitive. Everything else reuses
poker/retro patterns.

**Decision:** Only the **current drawer** emits strokes; the server
relays them to every other client and keeps a buffer for late-joiner
snapshots. Strokes are **batched** and coordinates **normalized**.

**A stroke** = a contiguous pen-down→pen-up path: an ordered list of
`[x, y]` points plus `color` and `width`. Coordinates are normalized
to **`0.0–1.0`** of the canvas box (not pixels) so every client
renders correctly at its own canvas size and the canvas stays
responsive.

**Batching:** the drawer's client accumulates points and flushes at
most every **~50ms** (or every N points) rather than one event per
`mousemove`. Mirrors how the music activity rate-limits note events
rather than streaming raw input. A monotonically increasing `seq`
per turn lets clients drop/coalesce out-of-order batches.

**Wire events** (drawer → server → others, on `chamber:<slug>`):

| Event | Payload | Meaning |
|---|---|---|
| `{:minigame, :stroke, batch}` | `%{seq, points: [[x,y],…], color, width}` | incremental segment of the in-progress stroke |
| `{:minigame, :stroke_end, seq}` | `seq` | pen up — the stroke with this seq is complete |
| `{:minigame, :undo}` | `nothing` | drawer removed their last completed stroke |
| `{:minigame, :clear}` | `nothing` | drawer cleared the canvas |

**Late-joiner snapshot:** `Chambers.Server` holds the turn's
completed strokes (`MiniGameState.strokes`, capped — see §6). On
mount/reload a client gets the full list in its initial
`minigame_view` and replays it onto the canvas, then follows live
batches. Same hydrate-then-follow model as retro's `:revealed`
payload and music's event buffer.

**Drawing tools (drawer only, minimal):** a small color palette
(~8 swatches), 3 brush sizes, eraser (= draw in the canvas
background color, kept simple in v1), **undo** (last stroke), and
**clear**. No fill, no shapes, no layers — out of scope.

**Why normalized coords + batching are non-negotiable:** pixel
coords break the moment two clients have different canvas widths
(everyone draws the music activity on phones too); unbatched
`mousemove` would flood PubSub. Both are the standard fixes and the
reason the "heaviest option" is still a few days, not a rewrite.

## 4. Words & guessing — _Locked_

**Decision:** The drawer is assigned a secret **word** from the
session's **word pack**; everyone else sees the word's **length as
blanks** (`_ _ _ _ _`). Guesses go through a server check.

**Word packs** (`word_packs.ex`, preset lists; host picks one in
`:lobby`): e.g. `:general`, `:animals`, `:movies`, `:office`. A
`:custom` pack (host pastes words in `:lobby`) is a polish item
(§9) — presets ship in v1. The drawer is offered a **choice of 3**
candidate words at turn start and picks one (standard Pictionary
affordance; avoids "I can't draw this").

**Guessing:**
- Guessers type into a text feed (chat-like). The server normalizes
  both the guess and the word (trim, downcase, collapse internal
  whitespace) and compares.
- **Correct guess:** that guesser is marked guessed, scores (§5), and
  is **locked out of further guessing this turn**. Their winning guess
  is **not** shown verbatim in the feed (it would leak the answer) —
  it renders as "**Alex guessed it!**" to everyone.
- **Wrong guess:** shown in the feed to everyone (it's part of the
  fun and the drawer's signal).
- The **drawer cannot guess**; their text input is replaced by the
  secret word display.
- A guess that's a near-miss (edit distance 1, or correct-minus-
  plural) can surface a private "**so close!**" to that guesser —
  polish (§9), not v1.

**Why length-as-blanks but not letter reveals:** length is a fair,
standard hint that helps guessers converge without giving the word
away. Progressive letter reveal (one letter every X seconds) is a
nice escalation but adds timer-coupled state — polish (§9).

## 5. Scoring — _Locked_

**Decision:** Both guessers and the drawer score; the scoreboard is
ephemeral (`%{user_id => points}`), reset on Play-again.

| Who | When | Points (v1 proposed formula) |
|---|---|---|
| **Guesser** | On correct guess | `50 + round(50 × time_remaining / turn_seconds)` — faster guesses score more, floor of 50, max 100. |
| **Drawer** | Per correct guesser | `25` each, capped at `100` per turn (4+ correct guessers ⇒ drawer maxes). Rewards a drawing that lands without dwarfing the guessers. |
| Anyone | No correct guess at all | Drawer **and** the room score 0 for the turn — the word was too hard or the drawing didn't land. |

The formula is the most tunable part of the spec — deliberately
simple, easy to re-balance after a play-test. It lives in
`pictionary.ex` so a tweak is one module, no wire change.

**Why time-scaled, not fixed:** a fixed "correct = 100" makes the
first and the last guesser equal and removes the race tension that
makes Pictionary fun. Time-scaling with a floor keeps later correct
guesses worth attempting.

## 6. Server-side state shape — _Locked_

**Decision:** One ephemeral struct, same null/cleared semantics as
`PokerSession` and retro's `EphemeralState`. `nil` when
`chamber.activity != "minigame"`; cleared on activity flip. **No
persistence** — the whole thing dies with the chamber, matching the
poker/§3.7 ephemeral decision. Drawings, scores, and word are all
ephemeral fun.

```elixir
defmodule Mixchamb.MiniGame.State do
  defstruct game: nil,            # :pictionary (registry key) | nil in idle
            phase: :lobby,        # framework + game phases (§1, §2)
            config: %{},          # %{word_pack, turn_seconds, round_count}
            players: [],          # ordered [user_id] — drawer rotation, seeded at Start
            round: 1,             # increments when the rotation wraps
            drawer_id: nil,       # whose turn it is
            word: nil,            # secret word (server-only; never in a guesser's view)
            word_choices: [],     # the 3 candidates offered to the drawer at turn start
            guessed: MapSet.new(),# user_ids who've guessed correctly this turn
            strokes: [],          # completed strokes for late-joiner snapshot (capped)
            scores: %{},          # %{user_id => points}
            turn_deadline: nil    # monotonic/utc deadline for timer expiry
end
```

**Stroke buffer cap:** `strokes` is bounded (proposed **2,000**
completed strokes per turn; further strokes drop the oldest with a
one-time "canvas is getting big" client hint, or simply ignore
beyond the cap). A turn is ~80s of one person drawing — 2,000 is
generous — but the cap protects ephemeral memory from a pathological
scribbler, same spirit as poker's 50-line queue cap.

**The `word` is server-only.** It appears in the drawer's `view/2`
output and in the `:turn_reveal` broadcast, never in a guesser's
view during `:turn`. This per-recipient filtering is why `view/2`
takes a `user_id` (§1).

PubSub broadcasts on the existing `chamber:<slug>` topic (drawing
events from §3 plus the framework/game events here):

| Event | Payload | Trigger |
|---|---|---|
| `{:minigame, :game_selected, game}` | registry key | host picks a game in `:lobby` |
| `{:minigame, :config_changed, config}` | full config map | host edits pack / timer / rounds in `:lobby` |
| `{:minigame, :started, snapshot}` | players + round + first drawer | host clicks Start |
| `{:minigame, :turn_started, %{drawer_id, blanks, round, deadline}}` | drawer id + word length (blanks) + round + deadline | a new turn begins (word itself only in the drawer's `view`) |
| `{:minigame, :guess, %{user_id, text}}` | wrong guesses only | a guesser submits a non-winning guess |
| `{:minigame, :guessed, %{user_id, order}}` | who got it + nth-correct | a guesser is correct (text withheld) |
| `{:minigame, :turn_revealed, %{word, scores}}` | the word + updated scoreboard | timer expiry / all guessed / host skip |
| `{:minigame, :game_over, scores}` | final scoreboard | last turn of last round resolved |
| `{:minigame, :reset, nothing}` | — | host Play-again (back to `:lobby`, scores cleared) |

(`:stroke` / `:stroke_end` / `:undo` / `:clear` from §3 round out
the set.)

## 7. Edge cases — _Locked_

| Case | Handling |
|---|---|
| **Drawer leaves mid-`:turn`** | Turn ends immediately → `:turn_reveal` with the word shown, drawer scores 0, guessers who already got it keep their points. Next turn proceeds with the rest of the rotation (the leaver is dropped from `players`). |
| **Guesser leaves mid-turn** | Their correct-guess points (if any) stay on the scoreboard for the game; they're dropped from `players` so they don't get a future drawing turn. |
| **Late joiner during `:turn`** | Spectator for this turn — gets the canvas snapshot (§3) and can **guess** (full points available; no penalty for arriving late, keeps it welcoming). Joins the rotation next round. |
| **Late joiner during `:lobby`** | Becomes a player at Start like everyone else. |
| **Late joiner during `:gameover`** | Sees the final scoreboard; becomes a player on Play-again. |
| **Everyone (non-drawer) guesses correctly** | Turn ends early → `:turn_reveal`. |
| **Nobody guesses before expiry** | `:turn_reveal`, word shown, 0 points all round for that turn. |
| **Only 2 players (1 drawer, 1 guesser)** | Valid. The single guesser races the clock solo; drawer caps at 25 (one correct guesser). Below 2 players, Start is disabled with a "Need at least 2 players" hint. |
| **Drawer reconnects (reload) mid-turn** | Their canvas + word + remaining time are restored from `MiniGameState` via `view/2`; they resume drawing. Strokes already buffered replay locally. |
| **Switch activity mid-game (minigame → music)** | Ephemeral `MiniGameState` is cleared (drawings + scores gone). Switching back starts a fresh `:lobby`. Same full-reset as poker (diverges from retro, which persists). |
| **Host leaves** | Co-host pattern (poker's multi-host, see `./planning-poker.md` polish iterations) drives. With no co-host, the game freezes until the creator returns; the per-turn timer pauses on a frozen game (no host to advance reveal). |
| **Guess equals the word with different case / spacing / trailing punctuation** | Correct — server normalizes (trim, downcase, collapse whitespace) both sides before compare. |
| **Drawer tries to guess / a guessed-out player guesses again** | Server rejects (`{:error, :not_allowed}`); client hides the input for both. |
| **Word pack exhausted in a long game** | Words are sampled without repeat within a game; if the pack runs dry, it refills (repeats allowed) rather than ending early. |
| **Stroke flood beyond the cap** | Oldest strokes drop (§6); live viewers already rendered them, only the late-joiner snapshot is lossy — acceptable for a transient game. |

## 8. Vue component split — _Locked_

**Decision:** Framework components at the top of
`assets/vue/activities/minigame/`, game-specific components nested
under a per-game sub-folder so the registry pattern is visible in the
file tree too.

```
assets/vue/activities/minigame/
├── MiniGameBoard.vue          # top-level, mounted when chamber.activity = "minigame";
│                              #   branches on phase → lobby / game stage / gameover
├── MiniGameLobby.vue          # game picker + roster + per-game config (host) / waiting (others)
├── MiniGameScoreboard.vue     # live + final scoreboard (shared across games)
├── MiniGameHostControls.vue   # Start / Skip turn / Next / Play again / End
└── pictionary/
    ├── PictionaryStage.vue    # orchestrates canvas + word/blanks + guess feed for a :turn
    ├── DrawingCanvas.vue      # the <canvas>, pointer handlers, stroke batching, tools (drawer);
    │                          #   replay + live-follow (everyone)
    └── GuessFeed.vue          # guess input + scrolling feed of wrong guesses / "X guessed it!"
```

The folder convention mirrors `assets/vue/activities/poker/` and
`assets/vue/activities/retro/`. A second game (e.g. Gartic Phone)
adds a `gartic_phone/` sub-folder beside `pictionary/` and a registry
entry — the framework files don't change.

**Why the canvas is its own component:** `DrawingCanvas.vue` is the
only place pointer events, the `requestAnimationFrame` render loop,
coordinate normalization, and stroke batching live. It exposes a
narrow prop/emit contract (`:strokes` to replay, `:is-drawer`,
`emit('stroke', batch)`) so it's testable in isolation and reusable
by any future canvas game.

**Activity gate / audio:** the `Chamber.vue` tap-to-enter gate
already covers non-music activities (poker shipped this — see
`./planning-poker.md` polish iterations). Minigame reuses it; the
gate heading branches to "Tap to join the game" and unlocks the
AudioContext so correct-guess / time-up cues (§9) can play.

## 9. Polish + nice-to-haves (not blocking v1) — _Locked_

Sized and considered, explicitly deferred so they don't get
re-debated each pass.

- ✅ **Gartic Phone as the second registry game** _(shipped
  2026-05-27)_. Telephone chains of write→draw→describe→draw…, then a
  synchronized album reveal. Reuses `DrawingCanvas.vue` in a new
  `local` (private, submit-as-blob) mode; books rotate one seat per
  step, missing submissions get a placeholder. `Mixchamb.MiniGame.GarticPhone`
  + `gartic_phone/GarticStage.vue` + a registry entry — no framework
  re-plumb, exactly as the registry promised.
- ✅ **Two Truths and a Lie** _(shipped 2026-05-27)_ — the absorbed
  icebreaker bucket. Content-free: everyone writes two truths + a lie,
  the room guesses which is the fib (+10 spot / +5 fool). The third
  registry game; `Mixchamb.MiniGame.TwoTruths` + `two_truths/TwoTruthsStage.vue`
  + a registry entry. Poll / would-you-rather remain easy future
  additions in the same vote/reveal vein.
- **Trivia.** Preset/host question sets with correct answers +
  timed rounds + a leaderboard. Moderate; another registry game.
- ✅ **Audio cues** _(shipped)_. Correct-guess blip + time-up buzzer +
  game-over fanfare in `assets/vue/lib/audio.ts` (`playGuessCorrect` /
  `playTimeUp` / `playGameOver`), wired in PictionaryStage +
  MiniGameBoard.
- ✅ **Progressive letter reveal** _(shipped)_. Letter positions are
  shuffled at choose-time; a server timer drips one every
  `turn_seconds/(cap+1)` up to ~half (words ≤3 letters reveal none).
  The view sends a `masked` string; guessers never get the full word.
- ✅ **Close-guess "so close!"** _(shipped)_. `Pictionary.near?/2`
  (plural / Levenshtein ≤1); near-miss emits a "close" feed with the
  text withheld from the room.
- ✅ **Custom word pack** _(shipped, ephemeral)_. Host pastes words in
  the lobby (`"custom"` pack, `config.custom_words`); the view sends
  only a count. Persisting a team's pack across sessions still needs
  the auth milestone (`../BRAINSTORM-v4.md` §7).
- ❌ **Save the drawing.** ~~Opt-in "keep this masterpiece" → a small
  gallery.~~ Dropped (2026-05-27) — the game is deliberately ephemeral;
  not worth the persistence layer.
- ✅ **Keyboard shortcuts** _(shipped)_: `1`–`8` brush color, `[` / `]`
  brush size, `E` eraser, `Z` undo (DrawingCanvas); `Enter` submits a
  guess (GuessFeed form).
- ✅ **Reconnect grace for the drawer** _(shipped)_. A non-host drawer
  dropping mid-turn starts a 5s hold (the host's presence sync drives
  it); they resume if they return, else the turn ends + they leave the
  rotation. Shown as "X disconnected — holding the turn…".

## Ready-to-build checklist — _Built_

Implementation order, sized in working-day units. **All steps built
and verified** (Elixir unit tests for the rules engine + a 3-browser
Playwright smoke; see end of section).

1. ✅ **Activity enum + lobby skeleton** — `"minigame"` added to
   `Chamber.activities()`; landing-page "Mini-game" card + in-chamber
   activity chip + `--accent-minigame` token; `MiniGameBoard.vue`
   renders the `:lobby` (game picker + roster + config).
2. ✅ **Game behaviour + registry + `MiniGameState`** — `MiniGame.Game`
   behaviour, `MiniGame.Registry`, `MiniGame.State` ephemeral struct,
   and `Chambers.Server` integration (`minigame_*` casts, `set_activity`
   clearing, broadcast helper, token-guarded turn timers). Pure-Elixir,
   unit-tested without the canvas.
3. ✅ **Pictionary game module** — turn rotation, word assignment +
   3-choice, guess normalization + correctness, time-scaled scoring,
   timer / phase advance, per-user `view/2` (drawer sees word).
   Heavily unit-tested (the rules engine).
4. ✅ **`DrawingCanvas.vue`** — pointer handlers, normalized coords,
   ~50ms stroke batching + `seq`, snapshot replay, live-follow of
   relayed batches, tools (palette / sizes / eraser / undo / clear).
5. ✅ **`PictionaryStage` + `GuessFeed` + `MiniGameScoreboard`** —
   canvas + blanks/word banner + timer, guess feed (withheld winning
   text), live scoreboard wired to the `minigame_*` events.
6. ✅ **Host controls + config** — Start (gated <2 players) / Skip /
   Next / Play-again / End; `:lobby` config (pack / timer / rounds).
7. ✅ **Smoke test** — 3-browser Playwright at
   `~/danceinthefake/tmp/mixchamb_minigame_smoke.mjs`: lobby → start →
   drawer draws (strokes replay on the other two) → guesser guesses
   right (lockout + score + withheld text) → all-guessed reveal (word
   + scores) → next turn rotates drawer → game over → play again.
   **17/17 assertions pass.**

The framework scaffolding (steps 1–2) is reused by every future game,
so game #2 should be far cheaper.

**Edge cases shipped (§7):** drawer-leave → auto-reveal + rotation
prune, and non-drawer-leave → roster prune, via `State.sync_presence/2`
(host-driven on every presence diff; unit-tested). Reconnect-grace
remains deferred polish (§9).

**Test surface:** `test/mixchamb/minigame/pictionary_test.exs`
(32 tests, rules + state + presence sync) + the Playwright smoke above.

---

## Notes for the implementing pass

- **Canvas rendering.** Keep a single `<canvas>` and a
  `requestAnimationFrame` loop that drains a queue of incoming
  batches; don't redraw the whole stroke list every frame except on
  resize/replay. On resize, rescale from the normalized coords —
  never store pixels.
- **Drawer input throttle.** Accumulate `pointermove` points and
  flush on a ~50ms interval (or every ~16 points), not per event.
  Use `pointer` events (not `mouse`) so touch/stylus work — phones
  are first-class here, same as the music pads.
- **Blanks display.** Render the word as `_` per letter with spaces
  preserved (multi-word answers show the gap), monospace so the
  blanks line up. The drawer's view swaps the blanks for the word in
  a muted "you're drawing: WORD" banner.
- **Guess feed.** A scrolling list; wrong guesses show `alias: text`,
  correct ones collapse to `✦ alias guessed it!` with an accent
  color. Auto-scroll to bottom unless the user has scrolled up.
- **Scoreboard.** Shared `MiniGameScoreboard.vue` sorts by points
  desc, highlights the current drawer, and animates point deltas on
  `:turn_revealed`. Reused unchanged by future games.
- **Timer.** Drive the countdown from the server-sent `deadline`
  (absolute), not a client interval started on receipt — late
  joiners and laggy clients then agree on time-left. The client
  interval is display-only.
- **Eraser.** v1 eraser = draw with the canvas background color at a
  larger width. A true erase (remove intersecting strokes) is more
  work than it's worth for a transient game.
