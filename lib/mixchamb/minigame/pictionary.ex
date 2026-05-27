defmodule Mixchamb.MiniGame.Pictionary do
  @moduledoc """
  The v1 mini-game: live draw-and-guess (mini-game.md §2–§5).

  Turn-based. One **drawer** per turn is assigned a secret word and
  draws it on a shared canvas; everyone else races to guess it via a
  text feed before the per-turn timer runs out. A **round** = every
  player has drawn once; a **game** = `round_count` rounds.

  This module is pure (no PubSub, no GenServer) so the rules engine is
  unit-testable in isolation — the GenServer drives the clock and fans
  out the effects this module returns. It operates on the shared
  `%Mixchamb.MiniGame.State{}`, mutating the game-specific fields.
  """

  @behaviour Mixchamb.MiniGame.Game

  alias Mixchamb.MiniGame.State
  alias Mixchamb.MiniGame.WordPacks

  @turn_seconds_options [60, 80, 120]
  @round_count_range 1..5
  @word_choice_count 3

  # Guesser scoring (spec §5): floor of 50 on any correct guess, +50
  # scaled by fraction of the turn still on the clock, capped at 100.
  @score_floor 50
  @score_bonus 50
  # Drawer scores per correct guesser, capped per turn so a popular
  # drawing rewards without dwarfing the guessers (spec §5).
  @drawer_points_per_guesser 25
  @drawer_points_cap 100

  ## --- Game behaviour: config ------------------------------------

  @impl true
  def default_config do
    %{word_pack: WordPacks.default(), turn_seconds: 80, round_count: 2, custom_words: []}
  end

  @impl true
  def min_players, do: 2

  @impl true
  def sanitize_config(current, partial) when is_map(current) and is_map(partial) do
    current
    |> apply_config(partial, "word_pack", :word_pack, &valid_pack/1)
    |> apply_config(partial, "turn_seconds", :turn_seconds, &clamp_turn_seconds/1)
    |> apply_config(partial, "round_count", :round_count, &clamp_round_count/1)
    |> apply_custom_words(partial)
  end

  # Preset pack id, or the host's "custom" list.
  defp valid_pack("custom"), do: "custom"
  defp valid_pack(p) when is_binary(p), do: if(WordPacks.valid?(p), do: p, else: false)
  defp valid_pack(_), do: false

  # Host-pasted custom words: trim, drop blanks + over-long entries,
  # dedupe, cap. Stored in config; never echoed to the client in full
  # (the view sends only a count) so guessers can't read the pack.
  @custom_word_max_len 40
  @custom_word_cap 200
  defp apply_custom_words(config, %{"custom_words" => words}) when is_list(words) do
    cleaned =
      words
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == "" or String.length(&1) > @custom_word_max_len))
      |> Enum.uniq()
      |> Enum.take(@custom_word_cap)

    Map.put(config, :custom_words, cleaned)
  end

  defp apply_custom_words(config, _), do: config

  defp apply_config(config, partial, str_key, atom_key, validate) do
    case Map.fetch(partial, str_key) do
      {:ok, raw} ->
        case validate.(coerce(raw)) do
          false -> config
          nil -> config
          valid -> Map.put(config, atom_key, valid)
        end

      :error ->
        config
    end
  end

  # Client may send numbers as strings; coerce the numeric ones.
  defp coerce(v) when is_binary(v) do
    case Integer.parse(v) do
      {n, ""} -> n
      _ -> v
    end
  end

  defp coerce(v), do: v

  defp clamp_turn_seconds(n) when n in @turn_seconds_options, do: n
  defp clamp_turn_seconds(_), do: false

  defp clamp_round_count(n) when is_integer(n) do
    if n in @round_count_range, do: n, else: false
  end

  defp clamp_round_count(_), do: false

  ## --- Game behaviour: lifecycle ---------------------------------

  @impl true
  def init(%State{players: [first | _]} = state) do
    begin_turn(state, first)
  end

  @impl true
  def advance(%State{phase: :turn} = state), do: to_reveal(state)
  def advance(%State{phase: :turn_reveal} = state), do: next_turn(state)
  def advance(%State{} = state), do: state

  ## --- Game behaviour: per-user view -----------------------------

  @impl true
  def view(%State{} = state, user_id) do
    is_drawer = user_id != nil and user_id == state.drawer_id
    reveal? = state.phase in [:turn_reveal, :gameover]
    show_word? = is_drawer or reveal?

    %{
      game: "pictionary",
      phase: Atom.to_string(state.phase),
      config: %{
        word_pack: state.config[:word_pack],
        turn_seconds: state.config[:turn_seconds],
        round_count: state.config[:round_count],
        # Count only — the custom words themselves never reach the
        # client, or guessers could read the pack.
        custom_word_count: length(state.config[:custom_words] || [])
      },
      round: state.round,
      round_count: state.config[:round_count],
      min_players: min_players(),
      players: state.players,
      drawer_id: state.drawer_id,
      is_drawer: is_drawer,
      # `word == nil` during `:turn` means the drawer is still
      # choosing — guessers see "X is choosing a word…".
      is_choosing: state.phase == :turn and state.word == nil,
      # The actual secret — only ever sent to the drawer (their turn)
      # or to everyone once the turn is revealed.
      word: if(show_word?, do: state.word),
      # Masked word: spaces preserved, hidden letters as "_", and any
      # progressively-revealed letters filled in (spec §4 + §9). Only
      # revealed letters reach a guesser — never the whole word.
      masked: masked_string(state, show_word?),
      # Drawer dropped and is in the reconnect-grace window.
      drawer_away: state.drawer_away,
      # The 3 candidate words, only to the drawer while choosing.
      word_choices:
        if(is_drawer and state.phase == :turn and state.word == nil,
          do: state.word_choices,
          else: []
        ),
      guessed: MapSet.to_list(state.guessed),
      scores: state.scores,
      # Absolute deadline (ms epoch) so every client agrees on
      # time-left regardless of latency (spec "Notes"). nil while
      # choosing / revealing.
      deadline: state.turn_deadline,
      # Completed strokes for late-joiner / reconnect replay (spec §3).
      strokes: state.strokes,
      # Bumps every turn so the client knows to reset its canvas.
      turn_token: state.turn_token
    }
  end

  ## --- Game behaviour: actions -----------------------------------

  @impl true
  # Drawer picks one of the 3 candidate words; the clock starts now.
  def handle_action(%State{phase: :turn, word: nil} = state, {:choose_word, word}, %{
        user_id: user_id
      }) do
    cond do
      user_id != state.drawer_id ->
        {:error, :not_drawer}

      word not in state.word_choices ->
        {:error, :not_a_choice}

      true ->
        deadline = now_ms() + state.config[:turn_seconds] * 1000

        new_state = %{
          state
          | word: word,
            word_choices: [],
            turn_deadline: deadline,
            used_words: [word | state.used_words],
            # Shuffle the letter positions so progressive reveal doesn't
            # always hand out the prefix (spec §9).
            reveal_order: letter_positions(word) |> Enum.shuffle(),
            revealed: 0
        }

        {:ok, new_state, [:changed]}
    end
  end

  def handle_action(%State{}, {:choose_word, _}, _ctx), do: {:error, :not_choosing}

  # A guess. Correct → score + lockout (+ maybe end the turn early);
  # wrong → just a feed line, no state change.
  def handle_action(%State{phase: :turn, word: word} = state, {:guess, text}, %{
        user_id: user_id,
        alias: alias_label
      })
      when is_binary(word) do
    cond do
      user_id == state.drawer_id ->
        {:error, :not_allowed}

      MapSet.member?(state.guessed, user_id) ->
        {:error, :already_guessed}

      not is_binary(text) or normalize(text) == "" ->
        {:error, :empty}

      normalize(text) == normalize(word) ->
        register_correct(state, user_id, alias_label)

      near?(normalize(text), normalize(word)) ->
        # Near-miss: withhold the text (one edit from the answer —
        # showing it to the room would leak the word). The guesser gets
        # a private "so close!"; everyone else just "X was close".
        {:ok, state,
         [{:feed, %{type: "close", user_id: user_id, alias: alias_label, text: text}}]}

      true ->
        {:ok, state,
         [{:feed, %{type: "wrong", user_id: user_id, alias: alias_label, text: text}}]}
    end
  end

  # Guess before the word is chosen, or outside a turn: rejected.
  def handle_action(%State{}, {:guess, _}, _ctx), do: {:error, :not_started}

  # Host skip — only meaningful mid-turn; jumps straight to reveal.
  def handle_action(%State{phase: :turn} = state, :skip, _ctx),
    do: {:ok, to_reveal(state), [:changed]}

  def handle_action(%State{}, :skip, _ctx), do: {:error, :not_turn}

  ## --- Internals -------------------------------------------------

  defp register_correct(state, user_id, alias_label) do
    order = MapSet.size(state.guessed) + 1
    points = guesser_points(state)

    scored = %{
      state
      | guessed: MapSet.put(state.guessed, user_id),
        scores: Map.update(state.scores, user_id, points, &(&1 + points))
    }

    feed = {:feed, %{type: "correct", user_id: user_id, alias: alias_label, order: order}}

    # Every non-drawer guessed → end the turn early (spec §2).
    if all_guessed?(scored) do
      {:ok, to_reveal(scored), [feed, :changed]}
    else
      {:ok, scored, [feed, :changed]}
    end
  end

  # Points for a correct guess: floor + bonus scaled by time left.
  defp guesser_points(state) do
    turn_ms = state.config[:turn_seconds] * 1000
    remaining = max(0, (state.turn_deadline || now_ms()) - now_ms())
    fraction = if turn_ms > 0, do: remaining / turn_ms, else: 0.0

    (@score_floor + round(@score_bonus * fraction))
    |> min(@score_floor + @score_bonus)
    |> max(@score_floor)
  end

  # Freeze the turn, tally the drawer's points, show the word.
  defp to_reveal(%State{} = state) do
    correct_count = MapSet.size(state.guessed)
    drawer_points = min(@drawer_points_per_guesser * correct_count, @drawer_points_cap)

    scores =
      if state.drawer_id && drawer_points > 0,
        do: Map.update(state.scores, state.drawer_id, drawer_points, &(&1 + drawer_points)),
        else: state.scores

    %{state | phase: :turn_reveal, turn_deadline: nil, scores: scores, drawer_away: false}
  end

  # Rotate to the next drawer; wrap → next round; past last round →
  # game over.
  defp next_turn(%State{players: players, drawer_id: drawer_id} = state) do
    idx = Enum.find_index(players, &(&1 == drawer_id)) || 0
    next_idx = idx + 1

    cond do
      next_idx < length(players) ->
        begin_turn(state, Enum.at(players, next_idx))

      state.round < state.config[:round_count] ->
        %{state | round: state.round + 1} |> begin_turn(List.first(players))

      true ->
        %{state | phase: :gameover, turn_deadline: nil, word: nil, word_choices: []}
    end
  end

  # Set up a fresh turn for `drawer_id`: new word choices, cleared
  # guesses + canvas, clock not yet running (starts on choose_word).
  defp begin_turn(%State{} = state, drawer_id) do
    choices = sample_words(state)

    %{
      state
      | phase: :turn,
        drawer_id: drawer_id,
        word: nil,
        word_choices: choices,
        guessed: MapSet.new(),
        strokes: [],
        turn_deadline: nil,
        turn_token: state.turn_token + 1,
        drawer_away: false,
        revealed: 0,
        reveal_order: []
    }
  end

  # Draw the turn's word choices: the host's custom list when the
  # "custom" pack is selected and non-empty, else the preset pack.
  defp sample_words(%State{config: %{word_pack: "custom", custom_words: cw}} = state)
       when cw != [] do
    WordPacks.sample_from(cw, @word_choice_count, state.used_words)
  end

  defp sample_words(%State{} = state) do
    WordPacks.sample(state.config[:word_pack], @word_choice_count, state.used_words)
  end

  # Every non-drawer player has a correct guess. Spectators (late
  # joiners not in `players`) are bonus and don't gate the early end.
  defp all_guessed?(%State{players: players, drawer_id: drawer_id, guessed: guessed}) do
    expected = players |> Enum.reject(&(&1 == drawer_id)) |> MapSet.new()
    expected != MapSet.new() and MapSet.subset?(expected, guessed)
  end

  # Grapheme indices of the non-space letters, for progressive reveal.
  defp letter_positions(word) do
    word
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.reject(fn {c, _} -> c == " " end)
    |> Enum.map(fn {_, i} -> i end)
  end

  # Build the masked word string: spaces kept, hidden letters "_",
  # revealed (or all, for the drawer / reveal phase) shown.
  defp masked_string(%State{word: nil}, _show_all?), do: ""

  defp masked_string(%State{word: word}, true), do: mask(word, :all)

  defp masked_string(%State{word: word, reveal_order: order, revealed: n}, false) do
    mask(word, order |> Enum.take(n) |> MapSet.new())
  end

  defp mask(word, :all) do
    word
    |> String.graphemes()
    |> Enum.map(fn
      " " -> " "
      c -> c
    end)
    |> Enum.join()
  end

  defp mask(word, %MapSet{} = revealed) do
    word
    |> String.graphemes()
    |> Enum.with_index()
    |> Enum.map(fn
      {" ", _} -> " "
      {c, i} -> if MapSet.member?(revealed, i), do: c, else: "_"
    end)
    |> Enum.join()
  end

  @doc """
  How many letters progressive reveal will ultimately show this turn —
  about half, and never the whole word. Words of 3 letters or fewer
  reveal nothing (one letter would give too much away). Exposed for the
  GenServer's reveal timer.
  """
  def reveal_cap(%State{reveal_order: order}) do
    n = length(order)
    if n <= 3, do: 0, else: div(n, 2)
  end

  @doc """
  Milliseconds between letter reveals — the turn split into `cap + 1`
  slices so the last letter lands near the end. Exposed for the timer.
  """
  def reveal_interval_ms(%State{config: %{turn_seconds: secs}} = state) do
    div(secs * 1000, reveal_cap(state) + 1)
  end

  @doc """
  Normalize a word/guess for comparison (spec §4, §7): downcase and
  strip everything but letters and digits, so case, spacing, and
  punctuation never cause a false miss ("Ice Cream!" == "ice-cream").
  Exposed for tests.
  """
  def normalize(text) when is_binary(text) do
    text
    |> String.downcase()
    |> String.replace(~r/[^\p{L}\p{N}]/u, "")
  end

  @doc """
  Near-miss test on two already-normalized strings (spec §4 "so
  close!"): a singular/plural difference or a single-character edit
  (Levenshtein ≤ 1). `false` for an exact match — that's handled as a
  correct guess upstream. Exposed for tests.
  """
  def near?(a, b) when is_binary(a) and is_binary(b) do
    cond do
      a == "" or b == "" -> false
      a == b -> false
      a == b <> "s" or b == a <> "s" -> true
      true -> levenshtein(a, b) <= 1
    end
  end

  # Standard Levenshtein over graphemes, two-row DP. Words are short,
  # so this is cheap and clearer than a banded ≤1 special case.
  defp levenshtein(a, b) do
    graphemes_b = String.graphemes(b)

    a
    |> String.graphemes()
    |> Enum.with_index(1)
    |> Enum.reduce(Enum.to_list(0..length(graphemes_b)), fn {ca, i}, prev ->
      {row, _diag} =
        graphemes_b
        |> Enum.with_index()
        |> Enum.reduce({[i], i - 1}, fn {cb, j}, {cur, diag} ->
          cost = if ca == cb, do: 0, else: 1
          deletion = Enum.at(prev, j + 1) + 1
          insertion = hd(cur) + 1
          substitution = diag + cost
          {[Enum.min([deletion, insertion, substitution]) | cur], Enum.at(prev, j + 1)}
        end)

      Enum.reverse(row)
    end)
    |> List.last()
  end

  defp now_ms, do: System.system_time(:millisecond)

  @doc false
  def turn_seconds_options, do: @turn_seconds_options
end
