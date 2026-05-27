defmodule Mixchamb.MiniGame.GarticPhone do
  @moduledoc """
  The second registry game (mini-game.md §9): a telephone chain of
  write → draw → describe → draw → … on private per-player surfaces,
  then a synchronized album reveal.

  Unlike Pictionary (turn-based, one shared canvas), every player acts
  **simultaneously** each step on their own surface, and only sees the
  one prior entry they're reacting to — so this is the framework's
  proof that a second game is a module, not a re-plumb. Drawing reuses
  `DrawingCanvas.vue`, but here each canvas is private and submitted as
  a blob (no live stroke relay).

  ## Books & rotation
  Each player starts one **book** (their seed phrase). Each step the
  books rotate one seat, so book `b`'s step-`s` entry is authored by
  player index `rem(b + s, n)` and a player at step `s` holds book
  `Integer.mod(pi - s, n)`. After `n` steps every book has passed
  through every player once. Entry kind alternates: even step = text
  (write / describe), odd step = drawing.

  All game-specific data lives in `state.game_state` (the shared
  `%State{}` keeps Pictionary's dedicated fields); the framework
  `phase` runs `:play → :album → :gameover`, and `turn_deadline` /
  `turn_token` are reused for the per-step clock + timer guard.
  """

  @behaviour Mixchamb.MiniGame.Game

  alias Mixchamb.MiniGame.State

  @step_seconds_options [45, 60, 90]
  @text_max 200
  @stroke_cap 2_000

  ## --- config ----------------------------------------------------

  @impl true
  def default_config, do: %{step_seconds: 60}

  # Needs 3+ so the chain actually drifts (write → draw → describe);
  # with 2 it'd just be write → draw.
  @impl true
  def min_players, do: 3

  @impl true
  def sanitize_config(current, partial) when is_map(current) and is_map(partial) do
    case partial["step_seconds"] |> coerce() do
      n when n in @step_seconds_options -> Map.put(current, :step_seconds, n)
      _ -> current
    end
  end

  defp coerce(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> v
    end
  end

  defp coerce(v), do: v

  ## --- lifecycle -------------------------------------------------

  @impl true
  def init(%State{players: players} = state) do
    n = length(players)

    gs = %{
      n: n,
      # book_index => %{step_index => entry}
      books: Map.new(0..(n - 1), &{&1, %{}}),
      step: 0,
      submitted: MapSet.new(),
      album: nil
    }

    %{
      state
      | phase: :play,
        turn_deadline: deadline(state),
        turn_token: state.turn_token + 1,
        game_state: gs
    }
  end

  @impl true
  # Timer / host force-advance.
  def advance(%State{phase: :play} = state), do: advance_step(state)
  def advance(%State{phase: :album} = state), do: album_next(state)
  def advance(%State{} = state), do: state

  ## --- actions ---------------------------------------------------

  @impl true
  # A player submits their entry for the current step (text or drawing).
  def handle_action(%State{phase: :play, game_state: gs} = state, {:submit, payload}, %{
        user_id: user_id
      }) do
    pi = player_index(state, user_id)

    cond do
      pi == nil ->
        {:error, :not_a_player}

      MapSet.member?(gs.submitted, user_id) ->
        {:error, :already_submitted}

      true ->
        book = Integer.mod(pi - gs.step, gs.n)
        entry = build_entry(gs.step, user_id, payload)
        books = put_in(gs.books, [book, gs.step], entry)
        submitted = MapSet.put(gs.submitted, user_id)
        gs = %{gs | books: books, submitted: submitted}
        state = %{state | game_state: gs}

        # Everyone in this round is done → advance immediately.
        if MapSet.size(submitted) >= gs.n,
          do: {:ok, advance_step(state), [:changed]},
          else: {:ok, state, [:changed]}
    end
  end

  def handle_action(%State{}, {:submit, _}, _ctx), do: {:error, :not_playing}

  # Host advances the album to the next page/book.
  def handle_action(%State{phase: :album} = state, :album_next, _ctx),
    do: {:ok, album_next(state), [:changed]}

  # Host force-advances a step that's waiting on stragglers.
  def handle_action(%State{phase: :play} = state, :skip, _ctx),
    do: {:ok, advance_step(state), [:changed]}

  def handle_action(%State{}, _action, _ctx), do: {:error, :not_allowed}

  ## --- per-user view ---------------------------------------------

  @impl true
  def view(%State{phase: :play, game_state: gs} = state, user_id) do
    pi = player_index(state, user_id)
    base = base_view(state, gs)

    if pi == nil do
      # Spectator / left player: no surface, just the waiting status.
      Map.merge(base, %{is_player: false, my_kind: nil, prompt: nil, submitted: true})
    else
      book = Integer.mod(pi - gs.step, gs.n)
      # The single prior entry this player reacts to (private). Step 0
      # has none — they write an original seed.
      prompt = if gs.step == 0, do: nil, else: wire_entry(gs.books[book][gs.step - 1])

      Map.merge(base, %{
        is_player: true,
        my_kind: step_kind(gs.step),
        prompt: prompt,
        submitted: MapSet.member?(gs.submitted, user_id)
      })
    end
  end

  def view(%State{phase: :album, game_state: gs} = state, _user_id) do
    %{book: b, page: page} = gs.album
    entries = gs.books[b]

    %{
      game: "gartic_phone",
      phase: "album",
      total_books: gs.n,
      album_book: b,
      album_page: page,
      # The book owner (who seeded it) + the chain up to the current
      # page — books are public during the reveal.
      book_owner: Enum.at(state.players, b),
      pages:
        0..page
        |> Enum.map(&wire_entry(entries[&1]))
        |> Enum.reject(&is_nil/1)
    }
  end

  def view(%State{phase: :gameover, game_state: gs} = state, _user_id) do
    # Final: every book, fully revealed, for a re-browse.
    %{
      game: "gartic_phone",
      phase: "gameover",
      total_books: gs[:n] || length(state.players),
      books:
        (gs[:books] || %{})
        |> Enum.sort_by(fn {b, _} -> b end)
        |> Enum.map(fn {b, entries} ->
          %{
            owner: Enum.at(state.players, b),
            pages:
              entries
              |> Enum.sort_by(fn {s, _} -> s end)
              |> Enum.map(fn {_, e} -> wire_entry(e) end)
          }
        end)
    }
  end

  def view(%State{} = state, _user_id),
    do: %{
      game: "gartic_phone",
      phase: Atom.to_string(state.phase),
      config: %{step_seconds: state.config[:step_seconds]},
      min_players: min_players()
    }

  ## --- internals -------------------------------------------------

  defp base_view(state, gs) do
    %{
      game: "gartic_phone",
      phase: "play",
      step: gs.step,
      total_steps: gs.n,
      player_count: gs.n,
      submitted_count: MapSet.size(gs.submitted),
      deadline: state.turn_deadline,
      turn_token: state.turn_token
    }
  end

  # Even steps are text (write / describe), odd steps are drawing.
  defp step_kind(step), do: if(rem(step, 2) == 0, do: "text", else: "drawing")

  defp build_entry(step, user_id, payload) do
    case step_kind(step) do
      "text" ->
        %{kind: "text", by: user_id, text: clean_text(payload["text"] || payload[:text])}

      "drawing" ->
        %{
          kind: "drawing",
          by: user_id,
          strokes: clean_strokes(payload["strokes"] || payload[:strokes])
        }
    end
  end

  # Placeholder entry for a player who never submitted this step (left
  # or timed out) — keeps the chain intact (spec §7 spirit).
  defp placeholder(step, user_id) do
    case step_kind(step) do
      "text" -> %{kind: "text", by: user_id, text: "(no answer)"}
      "drawing" -> %{kind: "drawing", by: user_id, strokes: []}
    end
  end

  defp clean_text(t) when is_binary(t), do: t |> String.trim() |> String.slice(0, @text_max)
  defp clean_text(_), do: ""

  defp clean_strokes(s) when is_list(s), do: Enum.take(s, @stroke_cap)
  defp clean_strokes(_), do: []

  # Wire shape for a stored entry (or nil if missing).
  defp wire_entry(nil), do: nil
  defp wire_entry(%{kind: "text"} = e), do: %{kind: "text", by: e.by, text: e.text}
  defp wire_entry(%{kind: "drawing"} = e), do: %{kind: "drawing", by: e.by, strokes: e.strokes}

  # Fill any missing submissions for the current step, then move on —
  # to the next step, or to the album once every book is complete.
  defp advance_step(%State{game_state: gs} = state) do
    books = fill_missing(gs.books, gs.step, state.players)
    next = gs.step + 1

    if next >= gs.n do
      %{
        state
        | phase: :album,
          turn_deadline: nil,
          game_state: %{gs | books: books, step: gs.n, album: %{book: 0, page: 0}}
      }
    else
      %{
        state
        | turn_deadline: deadline(state),
          turn_token: state.turn_token + 1,
          game_state: %{gs | books: books, step: next, submitted: MapSet.new()}
      }
    end
  end

  defp fill_missing(books, step, players) do
    n = length(players)

    Enum.reduce(0..(n - 1), books, fn pi, acc ->
      book = Integer.mod(pi - step, n)

      if get_in(acc, [book, step]) do
        acc
      else
        put_in(acc, [book, step], placeholder(step, Enum.at(players, pi)))
      end
    end)
  end

  defp album_next(%State{game_state: gs} = state) do
    %{book: b, page: page} = gs.album

    cond do
      page + 1 < gs.n -> %{state | game_state: %{gs | album: %{book: b, page: page + 1}}}
      b + 1 < gs.n -> %{state | game_state: %{gs | album: %{book: b + 1, page: 0}}}
      true -> %{state | phase: :gameover}
    end
  end

  defp player_index(%State{players: players}, user_id),
    do: Enum.find_index(players, &(&1 == user_id))

  defp deadline(%State{config: %{step_seconds: secs}}),
    do: System.system_time(:millisecond) + secs * 1000
end
