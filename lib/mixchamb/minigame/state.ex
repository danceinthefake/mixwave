defmodule Mixchamb.MiniGame.State do
  @moduledoc """
  Ephemeral mini-game state held by `Mixchamb.Chambers.Server`
  (mini-game.md §6). Same null/cleared semantics as the poker session
  and retro `EphemeralState`: `nil` when `chamber.activity != "minigame"`,
  cleared on activity flip. Nothing here is persisted — drawings,
  scores and the secret word all die with the chamber.

  This module owns the **framework** layer (mini-game.md §1): the
  lobby (game pick + per-game config), the roster→player seeding at
  Start, the scoreboard, and the host transitions (start / play-again
  / end). Everything game-specific is delegated to the chosen game
  module via the `Mixchamb.MiniGame.Game` behaviour, which mutates the
  game-specific fields (`word`, `drawer_id`, `guessed`, `strokes`, …)
  on this same struct.
  """

  alias __MODULE__
  alias Mixchamb.MiniGame.Registry

  @type phase :: :lobby | :turn | :turn_reveal | :gameover

  @type t :: %State{
          game: String.t() | nil,
          phase: phase(),
          config: map(),
          players: [String.t()],
          round: pos_integer(),
          drawer_id: String.t() | nil,
          word: String.t() | nil,
          word_choices: [String.t()],
          guessed: MapSet.t(),
          strokes: list(),
          scores: %{optional(String.t()) => integer()},
          turn_deadline: integer() | nil,
          turn_token: non_neg_integer(),
          used_words: [String.t()],
          drawer_away: boolean(),
          revealed: non_neg_integer(),
          reveal_order: [non_neg_integer()],
          game_state: map()
        }

  defstruct game: nil,
            phase: :lobby,
            config: %{},
            players: [],
            round: 1,
            drawer_id: nil,
            word: nil,
            word_choices: [],
            guessed: MapSet.new(),
            strokes: [],
            scores: %{},
            turn_deadline: nil,
            turn_token: 0,
            # Words already used this game, so the sampler doesn't
            # repeat within a game (spec §7). Server-only; never in a
            # client view.
            used_words: [],
            # Drawer dropped mid-turn and is inside the reconnect-grace
            # window (spec §9). Surfaced in the view as a "reconnecting…"
            # hint; cleared when they return or the turn ends.
            drawer_away: false,
            # Progressive letter reveal (spec §9): how many letters are
            # revealed so far, and the (shuffled) order positions are
            # revealed in. Both reset each turn.
            revealed: 0,
            reveal_order: [],
            # Generic per-game state bag for games beyond Pictionary
            # (Pictionary predates this and uses the dedicated fields
            # above; Gartic Phone keeps its books/step/etc. here).
            game_state: %{}

  # Completed strokes kept for the late-joiner snapshot. A turn is
  # ~80s of one person drawing, so this is generous; the cap just
  # protects ephemeral memory from a pathological scribbler (spec §6).
  @stroke_cap 2_000

  @doc """
  Fresh lobby state. The single registry game is pre-selected so the
  host lands on a ready-to-configure lobby rather than an empty
  picker; selecting another game (when one exists) resets config to
  that game's defaults.
  """
  def new do
    game = Registry.default()

    %State{
      game: game,
      phase: :lobby,
      config: Registry.module(game).default_config()
    }
  end

  @doc "Lobby-only: switch the selected game, resetting config to its defaults."
  def select_game(%State{phase: :lobby} = state, game) do
    if Registry.valid?(game) do
      {:ok, %{state | game: game, config: Registry.module(game).default_config()}}
    else
      {:error, :unknown_game}
    end
  end

  def select_game(_state, _game), do: {:error, :not_lobby}

  @doc """
  Lobby-only: merge a partial config map (string-keyed, from the
  client) onto the current config, dropping unknown keys and clamping
  to the game's allowed values.
  """
  def set_config(%State{phase: :lobby} = state, partial) when is_map(partial) do
    merged = Registry.module(state.game).sanitize_config(state.config, partial)
    {:ok, %{state | config: merged}}
  end

  def set_config(_state, _partial), do: {:error, :not_lobby}

  @doc """
  Start the game from the current roster. `player_ids` is the live
  presence order (mini-game.md §1: "anyone present at Start is a
  player"). Requires ≥2 players. Seeds the rotation, resets scores,
  then hands off to the game module's `init/1` for the first turn.
  """
  def start(%State{phase: :lobby} = state, player_ids)
      when is_list(player_ids) do
    players = Enum.uniq(player_ids)

    if length(players) >= Registry.module(state.game).min_players() do
      seeded = %{
        state
        | players: players,
          round: 1,
          scores: Map.new(players, &{&1, 0}),
          used_words: []
      }

      {:ok, Registry.module(state.game).init(seeded)}
    else
      {:error, :need_more_players}
    end
  end

  def start(_state, _players), do: {:error, :not_lobby}

  @doc """
  Reset back to a fresh lobby, scores cleared (mini-game.md §1
  Play-again / End — both land here in v1; the lobby *is* the
  "no game running" screen). Keeps the selected game + config so the
  host can immediately Start again.
  """
  def to_lobby(%State{} = state) do
    %{
      state
      | phase: :lobby,
        players: [],
        round: 1,
        drawer_id: nil,
        word: nil,
        word_choices: [],
        guessed: MapSet.new(),
        strokes: [],
        scores: %{},
        turn_deadline: nil,
        used_words: [],
        drawer_away: false,
        revealed: 0,
        reveal_order: [],
        game_state: %{}
    }
  end

  @doc "Prune the rotation to `present_ids`, preserving order (spec §7)."
  def prune_players(%State{} = state, present_ids) when is_list(present_ids) do
    present = MapSet.new(present_ids)
    %{state | players: Enum.filter(state.players, &MapSet.member?(present, &1))}
  end

  @doc """
  Reconcile the rotation with who's actually present (spec §7).
  Returns:
  - `{:drawer_left, pruned}` — the drawer vanished mid-`:turn`; the
    caller should advance straight to reveal.
  - `{:roster_changed, pruned}` — a non-drawer left; rotation pruned
    so they don't get a future turn (their score stays).
  - `:noop` — nothing relevant changed, or not in a game phase.

  Only acts during `:turn` / `:turn_reveal`; lobby rosters are
  recomputed fresh from presence at Start, and `:gameover` keeps the
  final board intact for late arrivals.
  """
  def sync_presence(%State{phase: phase} = state, present_ids)
      when phase in [:turn, :turn_reveal] and is_list(present_ids) do
    present = MapSet.new(present_ids)
    players = Enum.filter(state.players, &MapSet.member?(present, &1))

    cond do
      phase == :turn and state.drawer_id not in present_ids ->
        {:drawer_left, %{state | players: players}}

      players != state.players ->
        {:roster_changed, %{state | players: players}}

      true ->
        :noop
    end
  end

  def sync_presence(%State{}, _present_ids), do: :noop

  ## --- Stroke buffer (used by the GenServer's stroke relay) -------

  @doc """
  Append a completed stroke to the late-joiner snapshot buffer,
  dropping the oldest once the cap is hit (spec §6). Live viewers
  have already rendered it; only the snapshot is lossy past the cap.
  """
  def push_stroke(%State{strokes: strokes} = state, stroke) do
    next = strokes ++ [stroke]

    next =
      if length(next) > @stroke_cap do
        Enum.drop(next, length(next) - @stroke_cap)
      else
        next
      end

    %{state | strokes: next}
  end

  @doc "Drawer's undo — drop the most recently completed stroke."
  def pop_stroke(%State{strokes: []} = state), do: state

  def pop_stroke(%State{strokes: strokes} = state),
    do: %{state | strokes: Enum.drop(strokes, -1)}

  @doc "Drawer cleared the canvas."
  def clear_strokes(%State{} = state), do: %{state | strokes: []}

  @doc "The stroke cap, exposed for tests."
  def stroke_cap, do: @stroke_cap
end
