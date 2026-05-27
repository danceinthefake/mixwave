defmodule Mixchamb.MiniGame.Game do
  @moduledoc """
  Behaviour every mini-game in the registry implements (mini-game.md
  §1). The framework (`Mixchamb.MiniGame.State`) owns the lobby,
  roster, scoreboard and host controls; a game module owns its own
  phase rules, what a "turn" means, and scoring.

  All callbacks take and return the shared `%Mixchamb.MiniGame.State{}`
  — game-specific data lives in that struct's `word` / `drawer_id` /
  `guessed` / … fields (spec §6) so the framework never has to know a
  game's internals. Adding a game is one module implementing this
  behaviour + one Vue stage component + one registry entry; no new
  activity, no migration, no `chamber_live.ex` plumbing beyond the
  existing `minigame_*` events.

  Functions return either an updated state, or `{:error, reason}` for
  a rejected action (the GenServer swallows the error and leaves state
  untouched — same shape as the poker/retro casts).
  """

  alias Mixchamb.MiniGame.State

  @typedoc "A correct/wrong/illegal guess outcome."
  @type guess_result ::
          {:correct, State.t(), order :: pos_integer()}
          | {:wrong, State.t()}
          | {:error, term()}

  @doc """
  Seed the first turn from the framework-seeded roster. Called once
  by `State.start/2` after `players` / `round` are set. Returns the
  state with the game's opening phase + first turn in place.
  """
  @callback init(State.t()) :: State.t()

  @doc """
  Per-recipient wire payload. `user_id` is `nil` for an
  un-authenticated/observer render. This is where the drawer sees the
  secret word while guessers see only blanks (spec §1, §4) — same
  "wire carries more than the UI shows" idea as poker/retro vote
  events, but resolved per recipient.
  """
  @callback view(State.t(), user_id :: String.t() | nil) :: map()

  @doc """
  Advance the turn/round clock — fired by timer expiry, the host's
  "next" button, or every-non-drawer-guessed. Returns the next state
  (which may be `:gameover`).
  """
  @callback advance(State.t()) :: State.t()

  @doc "Default per-game config map shown in the lobby (pack/timer/rounds…)."
  @callback default_config() :: map()

  @doc "Fewest players the game needs to start (Pictionary 2, Gartic 3)."
  @callback min_players() :: pos_integer()

  @doc """
  Merge a client-supplied (string-keyed) partial config onto the
  current config, dropping unknown keys and clamping values to the
  game's allowed set. Called from the lobby on every config change.
  """
  @callback sanitize_config(current :: map(), partial :: map()) :: map()

  @typedoc """
  Side effects the GenServer should fan out after an action. `:changed`
  triggers a full per-user view reload (scoreboard/phase/blanks…);
  `{:feed, payload}` pushes a transient guess-feed entry that isn't
  part of reloadable state (spec §4 guessing feed).
  """
  @type effect :: :changed | {:feed, map()}

  @doc """
  Apply a player/host action. `ctx` carries the acting `:user_id` and,
  for guesses, the resolved `:alias` for the feed line. Returns the
  new state plus the effects to broadcast, or `{:error, reason}` to
  reject (the GenServer then leaves state untouched).

  Actions (Pictionary): `{:choose_word, word}`, `{:guess, text}`,
  `:skip`.
  """
  @callback handle_action(State.t(), action :: term(), ctx :: map()) ::
              {:ok, State.t(), [effect()]} | {:error, term()}
end
