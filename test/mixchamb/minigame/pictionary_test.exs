defmodule Mixchamb.MiniGame.PictionaryTest do
  use ExUnit.Case, async: true

  alias Mixchamb.MiniGame.{Pictionary, State}

  # Start a 3-player game (p1, p2, p3) sitting in :turn with p1 as the
  # drawer, word not yet chosen. round_count defaults to 2.
  defp started(players \\ ~w(p1 p2 p3)) do
    {:ok, state} = State.start(State.new(), players)
    state
  end

  defp choose(state, word) do
    {:ok, s, _} =
      Pictionary.handle_action(state, {:choose_word, word}, %{user_id: state.drawer_id})

    s
  end

  describe "State.new/0 + lobby" do
    test "fresh lobby has pictionary pre-selected with default config" do
      s = State.new()
      assert s.game == "pictionary"
      assert s.phase == :lobby

      assert s.config == %{
               word_pack: "general",
               turn_seconds: 80,
               round_count: 2,
               custom_words: []
             }

      assert s.players == []
      assert s.scores == %{}
    end

    test "select_game rejects an unknown game and non-lobby phases" do
      assert {:error, :unknown_game} = State.select_game(State.new(), "nope")
      assert {:ok, %State{game: "pictionary"}} = State.select_game(State.new(), "pictionary")
      assert {:error, :not_lobby} = State.select_game(started(), "pictionary")
    end

    test "set_config clamps each field and ignores junk" do
      s = State.new()
      {:ok, s} = State.set_config(s, %{"word_pack" => "animals"})
      assert s.config[:word_pack] == "animals"

      {:ok, s} = State.set_config(s, %{"word_pack" => "does-not-exist"})
      assert s.config[:word_pack] == "animals", "invalid pack keeps the prior value"

      {:ok, s} = State.set_config(s, %{"turn_seconds" => "60"})
      assert s.config[:turn_seconds] == 60, "string numbers coerce"

      {:ok, s} = State.set_config(s, %{"turn_seconds" => 999})
      assert s.config[:turn_seconds] == 60, "out-of-range timer rejected"

      {:ok, s} = State.set_config(s, %{"round_count" => 4})
      assert s.config[:round_count] == 4

      {:ok, s} = State.set_config(s, %{"round_count" => 99})
      assert s.config[:round_count] == 4
    end

    test "set_config rejected outside the lobby" do
      assert {:error, :not_lobby} = State.set_config(started(), %{"turn_seconds" => 60})
    end
  end

  describe "State.start/2" do
    test "needs at least two players" do
      assert {:error, :need_more_players} = State.start(State.new(), ["solo"])
      assert {:error, :need_more_players} = State.start(State.new(), [])
    end

    test "seeds rotation, scores, and the first turn" do
      s = started(~w(a b c))
      assert s.phase == :turn
      assert s.players == ~w(a b c)
      assert s.drawer_id == "a"
      assert s.round == 1
      assert s.scores == %{"a" => 0, "b" => 0, "c" => 0}
      assert is_nil(s.word)
      assert length(s.word_choices) == 3
      assert s.turn_token > 0
    end

    test "is rejected once a game is running" do
      assert {:error, :not_lobby} = State.start(started(), ~w(x y))
    end
  end

  describe "choose_word" do
    test "drawer picks one of the three; the clock starts" do
      s = started()
      word = hd(s.word_choices)
      {:ok, s2, [:changed]} = Pictionary.handle_action(s, {:choose_word, word}, %{user_id: "p1"})
      assert s2.word == word
      assert s2.word_choices == []
      assert is_integer(s2.turn_deadline)
      assert word in s2.used_words
    end

    test "a non-drawer cannot choose" do
      s = started()

      assert {:error, :not_drawer} =
               Pictionary.handle_action(s, {:choose_word, hd(s.word_choices)}, %{user_id: "p2"})
    end

    test "a word outside the three offered is rejected" do
      s = started()

      assert {:error, :not_a_choice} =
               Pictionary.handle_action(s, {:choose_word, "definitely-not-offered"}, %{
                 user_id: "p1"
               })
    end

    test "auto-pick (choice timeout) picks the first candidate as the drawer" do
      # The server's word-choice timeout dispatches exactly this.
      s = started()
      first = hd(s.word_choices)

      {:ok, s2, [:changed]} =
        Pictionary.handle_action(s, {:choose_word, first}, %{user_id: s.drawer_id})

      assert s2.word == first
      assert is_integer(s2.turn_deadline)
    end
  end

  describe "guessing" do
    setup do
      s = started() |> choose_known("apple")
      {:ok, state: s}
    end

    # Force a known word so the test can submit a matching guess.
    defp choose_known(state, word) do
      state = %{state | word_choices: [word | state.word_choices]}
      choose(state, word)
    end

    test "the drawer cannot guess", %{state: s} do
      assert {:error, :not_allowed} =
               Pictionary.handle_action(s, {:guess, "apple"}, %{user_id: "p1", alias: "P1"})
    end

    test "a wrong guess emits a feed line but doesn't change state", %{state: s} do
      assert {:ok, ^s, [{:feed, feed}]} =
               Pictionary.handle_action(s, {:guess, "banana"}, %{user_id: "p2", alias: "P2"})

      assert feed == %{type: "wrong", user_id: "p2", alias: "P2", text: "banana"}
    end

    test "a correct guess scores, locks out, and withholds the text", %{state: s} do
      {:ok, s2, effects} =
        Pictionary.handle_action(s, {:guess, "apple"}, %{user_id: "p2", alias: "P2"})

      assert MapSet.member?(s2.guessed, "p2")
      assert s2.scores["p2"] >= 50

      assert {:feed, %{type: "correct", user_id: "p2", order: 1}} =
               List.keyfind(effects, :feed, 0)

      refute Enum.any?(effects, &match?({:feed, %{text: _}}, &1)), "winning text not leaked"

      # Locked out of a second guess.
      assert {:error, :already_guessed} =
               Pictionary.handle_action(s2, {:guess, "apple"}, %{user_id: "p2", alias: "P2"})
    end

    test "normalization ignores case, spacing, and punctuation", %{state: _} do
      s = started() |> choose_known("ice cream")

      {:ok, s2, _} =
        Pictionary.handle_action(s, {:guess, "  ICE-cream! "}, %{user_id: "p2", alias: "P2"})

      assert MapSet.member?(s2.guessed, "p2")
    end

    test "an empty guess is rejected", %{state: s} do
      assert {:error, :empty} =
               Pictionary.handle_action(s, {:guess, "   "}, %{user_id: "p2", alias: "P2"})
    end

    test "a guess before the word is chosen is rejected" do
      s = started()

      assert {:error, :not_started} =
               Pictionary.handle_action(s, {:guess, "apple"}, %{user_id: "p2", alias: "P2"})
    end
  end

  describe "turn end + scoring" do
    test "all non-drawers guessing ends the turn early and tallies the drawer" do
      # 2 players: p1 draws, p2 is the only guesser.
      s = started(~w(p1 p2)) |> force_word("apple")
      {:ok, s2, _} = Pictionary.handle_action(s, {:guess, "apple"}, %{user_id: "p2", alias: "P2"})

      assert s2.phase == :turn_reveal, "every non-drawer guessed → reveal"
      # Drawer scores 25 per correct guesser (1 here).
      assert s2.scores["p1"] == 25
      assert s2.scores["p2"] >= 50
    end

    test "host skip jumps to reveal; nobody guessed → drawer scores 0" do
      s = started(~w(p1 p2)) |> force_word("apple")
      {:ok, s2, [:changed]} = Pictionary.handle_action(s, :skip, %{user_id: "p1"})
      assert s2.phase == :turn_reveal
      assert s2.scores["p1"] == 0
    end

    test "drawer points cap at 100 with many guessers" do
      players = for n <- 1..6, do: "p#{n}"
      s = started(players) |> force_word("apple")

      s =
        Enum.reduce(2..6, s, fn n, acc ->
          {:ok, acc2, _} =
            Pictionary.handle_action(acc, {:guess, "apple"}, %{user_id: "p#{n}", alias: "P#{n}"})

          acc2
        end)

      assert s.phase == :turn_reveal
      assert s.scores["p1"] == 100, "5 guessers × 25 = 125, capped at 100"
    end

    defp force_word(state, word) do
      state = %{state | word_choices: [word | state.word_choices]}
      choose(state, word)
    end
  end

  describe "rotation + game over" do
    test "advance rotates the drawer, wraps into the next round, then ends" do
      # round_count 1 keeps it short: 2 players → 2 turns → game over.
      {:ok, s} = State.set_config(State.new(), %{"round_count" => 1})
      {:ok, s} = State.start(s, ~w(a b))
      assert s.drawer_id == "a" and s.round == 1

      # Turn 1 reveal → next turn (drawer b).
      s = %{s | phase: :turn_reveal}
      s = Pictionary.advance(s)
      assert s.phase == :turn and s.drawer_id == "b" and s.round == 1

      # Turn 2 reveal → rotation wraps, round_count reached → game over.
      s = %{s | phase: :turn_reveal}
      s = Pictionary.advance(s)
      assert s.phase == :gameover
    end

    test "two rounds: rotation wraps once before the final round ends it" do
      {:ok, s} = State.set_config(State.new(), %{"round_count" => 2})
      {:ok, s} = State.start(s, ~w(a b))

      phases =
        Enum.map_reduce(1..4, s, fn _, acc ->
          acc = %{acc | phase: :turn_reveal}
          acc = Pictionary.advance(acc)
          {{acc.phase, acc.drawer_id, acc.round}, acc}
        end)
        |> elem(0)

      assert phases == [
               {:turn, "b", 1},
               {:turn, "a", 2},
               {:turn, "b", 2},
               {:gameover, "b", 2}
             ]
    end
  end

  describe "per-user view" do
    test "drawer sees the word; guessers see only blanks while drawing" do
      s = started(~w(p1 p2)) |> view_word("apple")

      drawer = Pictionary.view(s, "p1")
      guesser = Pictionary.view(s, "p2")

      assert drawer.word == "apple"
      assert drawer.is_drawer
      assert is_nil(guesser.word)
      refute guesser.is_drawer
      assert guesser.masked == "_____"
    end

    test "word_choices only reach the drawer while choosing" do
      s = started(~w(p1 p2))
      assert Pictionary.view(s, "p1").word_choices == s.word_choices
      assert Pictionary.view(s, "p2").word_choices == []
      assert Pictionary.view(s, "p1").is_choosing
    end

    test "reveal shows the word to everyone" do
      s = started(~w(p1 p2)) |> view_word("apple")
      s = %{s | phase: :turn_reveal}
      assert Pictionary.view(s, "p2").word == "apple"
    end

    test "masked keeps spaces and underscores for hidden multi-word answers" do
      s = started(~w(p1 p2)) |> view_word("ice cream")
      assert Pictionary.view(s, "p2").masked == "___ _____"
      # The drawer / reveal view shows it in full.
      assert Pictionary.view(s, "p1").masked == "ice cream"
    end

    defp view_word(state, word) do
      state = %{state | word_choices: [word | state.word_choices]}
      choose(state, word)
    end
  end

  describe "progressive letter reveal (spec §9)" do
    test "reveal_cap is ~half the letters, never the whole word" do
      s = started(~w(p1 p2)) |> view_word("scarecrow")
      # 9 letters → cap 4 (never all 9).
      assert Pictionary.reveal_cap(s) == 4
      assert Pictionary.reveal_interval_ms(s) > 0
    end

    test "short words reveal nothing" do
      s = started(~w(p1 p2)) |> view_word("ox")
      assert Pictionary.reveal_cap(s) == 0
    end

    test "revealed letters fill into the guesser's mask; the rest stay hidden" do
      s = started(~w(p1 p2)) |> view_word("planet")
      # Reveal the first two positions of the (shuffled) reveal order.
      s = %{s | revealed: 2}
      masked = Pictionary.view(s, "p2").masked

      assert String.length(masked) == 6
      # Exactly two letters shown, four underscores — never the full word.
      assert masked |> String.graphemes() |> Enum.count(&(&1 == "_")) == 4
      refute masked == "planet"
    end
  end

  describe "prune_players (reconnect-grace support)" do
    test "keeps only present players, preserving order" do
      s = started(~w(a b c))
      assert State.prune_players(s, ~w(c a)).players == ~w(a c)
    end
  end

  describe "sync_presence (spec §7)" do
    test "drawer leaving mid-turn signals :drawer_left and prunes them" do
      s = started(~w(p1 p2 p3))
      assert s.drawer_id == "p1"
      assert {:drawer_left, pruned} = State.sync_presence(s, ~w(p2 p3))
      assert pruned.players == ~w(p2 p3)
    end

    test "a non-drawer leaving signals :roster_changed, keeping the drawer" do
      s = started(~w(p1 p2 p3))
      assert {:roster_changed, pruned} = State.sync_presence(s, ~w(p1 p2))
      assert pruned.players == ~w(p1 p2)
      assert pruned.drawer_id == "p1"
    end

    test "no change when everyone's still present" do
      s = started(~w(p1 p2 p3))
      assert :noop = State.sync_presence(s, ~w(p1 p2 p3))
    end

    test "lobby + gameover are left untouched" do
      assert :noop = State.sync_presence(State.new(), ~w(p1))
      over = %{started(~w(p1 p2)) | phase: :gameover}
      assert :noop = State.sync_presence(over, [])
    end
  end

  describe "stroke buffer" do
    test "push / pop / clear" do
      s = State.new()
      s = State.push_stroke(s, %{"points" => [[0.1, 0.1]]})
      s = State.push_stroke(s, %{"points" => [[0.2, 0.2]]})
      assert length(s.strokes) == 2

      s = State.pop_stroke(s)
      assert length(s.strokes) == 1

      s = State.clear_strokes(s)
      assert s.strokes == []
    end

    test "caps the buffer, dropping oldest" do
      cap = State.stroke_cap()

      s =
        Enum.reduce(1..(cap + 5), State.new(), fn i, acc ->
          State.push_stroke(acc, %{"i" => i})
        end)

      assert length(s.strokes) == cap
      assert List.first(s.strokes) == %{"i" => 6}, "oldest five dropped"
    end
  end

  describe "normalize/1" do
    test "strips case, whitespace, and punctuation" do
      assert Pictionary.normalize("Ice Cream!") == "icecream"
      assert Pictionary.normalize("spider-man") == "spiderman"
      assert Pictionary.normalize("  Hello,  World  ") == "helloworld"
    end
  end

  describe "near?/2 (close-guess)" do
    test "single edit + plural are near; exact + far are not" do
      assert Pictionary.near?("rabit", "rabbit")
      assert Pictionary.near?("cats", "cat")
      assert Pictionary.near?("hose", "house")
      refute Pictionary.near?("cat", "cat")
      refute Pictionary.near?("dog", "cat")
      refute Pictionary.near?("", "cat")
    end

    test "a near-miss guess emits a 'close' feed (text withheld from the room)" do
      s = started(~w(p1 p2)) |> force_word("rabbit")

      {:ok, ^s, [{:feed, feed}]} =
        Pictionary.handle_action(s, {:guess, "rabit"}, %{user_id: "p2", alias: "P2"})

      assert feed.type == "close"
      assert feed.user_id == "p2"
      # The text is carried (the guesser sees it privately) but the
      # type marks it so the room view withholds it.
      assert feed.text == "rabit"
    end
  end

  describe "custom word pack" do
    test "sanitize cleans, dedupes, and caps the pasted list" do
      {:ok, s} = State.select_game(State.new(), "pictionary")
      {:ok, s} = State.set_config(s, %{"word_pack" => "custom"})
      assert s.config[:word_pack] == "custom"

      {:ok, s} =
        State.set_config(s, %{
          "custom_words" => ["  Cat ", "cat", "", "dog", String.duplicate("x", 99)]
        })

      # trimmed + de-duped ("Cat"/"cat" → "Cat","cat" are distinct after
      # trim only; blanks + the 99-char entry dropped)
      assert "Cat" in s.config[:custom_words]
      assert "dog" in s.config[:custom_words]
      refute "" in s.config[:custom_words]
      refute Enum.any?(s.config[:custom_words], &(String.length(&1) > 40))
    end

    test "turn draws words from the custom list when selected + non-empty" do
      {:ok, s} = State.set_config(State.new(), %{"word_pack" => "custom"})
      {:ok, s} = State.set_config(s, %{"custom_words" => ~w(alpha bravo charlie delta)})
      {:ok, s} = State.start(s, ~w(p1 p2))

      assert Enum.all?(s.word_choices, &(&1 in ~w(alpha bravo charlie delta)))
    end

    test "the view sends a custom_word_count, never the words" do
      {:ok, s} = State.set_config(State.new(), %{"word_pack" => "custom"})
      {:ok, s} = State.set_config(s, %{"custom_words" => ~w(secretword another)})
      view = Pictionary.view(s, "p1")
      assert view.config.custom_word_count == 2
      refute Map.has_key?(view.config, :custom_words)
    end
  end
end
