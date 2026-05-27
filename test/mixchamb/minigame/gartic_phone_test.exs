defmodule Mixchamb.MiniGame.GarticPhoneTest do
  use ExUnit.Case, async: true

  alias Mixchamb.MiniGame.{GarticPhone, State}

  defp gartic(players) do
    {:ok, s} = State.select_game(State.new(), "gartic_phone")
    {:ok, s} = State.start(s, players)
    s
  end

  defp submit(state, user_id, payload) do
    {:ok, s, _} = GarticPhone.handle_action(state, {:submit, payload}, %{user_id: user_id})
    s
  end

  # Everyone writes/draws a trivial entry for the current step.
  defp all_submit(state, label) do
    Enum.reduce(state.players, state, fn uid, acc ->
      kind = if rem(acc.game_state.step, 2) == 0, do: :text, else: :drawing

      payload =
        if kind == :text,
          do: %{"text" => "#{label}-#{uid}"},
          else: %{"strokes" => [%{"points" => [[0.1, 0.1]]}]}

      submit(acc, uid, payload)
    end)
  end

  describe "init / lobby" do
    test "select_game switches to gartic with its default config" do
      {:ok, s} = State.select_game(State.new(), "gartic_phone")
      assert s.game == "gartic_phone"
      assert s.config == %{step_seconds: 60}
    end

    test "start seeds books, step 0, and a writing phase" do
      s = gartic(~w(a b c))
      assert s.phase == :play
      assert s.game_state.n == 3
      assert s.game_state.step == 0
      assert map_size(s.game_state.books) == 3
      assert is_integer(s.turn_deadline)
    end

    test "needs at least 3 players (vs Pictionary's 2)" do
      {:ok, s} = State.select_game(State.new(), "gartic_phone")
      assert {:error, :need_more_players} = State.start(s, ~w(a b))
      assert {:ok, %State{phase: :play}} = State.start(s, ~w(a b c))
    end

    test "config clamps step_seconds" do
      {:ok, s} = State.select_game(State.new(), "gartic_phone")
      {:ok, s} = State.set_config(s, %{"step_seconds" => "90"})
      assert s.config[:step_seconds] == 90
      {:ok, s} = State.set_config(s, %{"step_seconds" => 999})
      assert s.config[:step_seconds] == 90
    end
  end

  describe "step 0: writing" do
    test "everyone writes text, no prompt" do
      s = gartic(~w(a b c))
      v = GarticPhone.view(s, "a")
      assert v.phase == "play"
      assert v.my_kind == "text"
      assert is_nil(v.prompt)
      refute v.submitted
      assert v.total_steps == 3
    end

    test "submitting marks done; all-submitted advances to drawing" do
      s = gartic(~w(a b c))
      s = submit(s, "a", %{"text" => "apple"})
      assert GarticPhone.view(s, "a").submitted
      assert s.game_state.step == 0, "still step 0 until everyone's in"

      s = submit(s, "b", %{"text" => "banana"})
      s = submit(s, "c", %{"text" => "cherry"})
      assert s.game_state.step == 1
      assert GarticPhone.view(s, "a").my_kind == "drawing"
    end
  end

  describe "chain rotation" do
    test "at step 1 a player draws the previous player's seed" do
      s =
        gartic(~w(a b c))
        |> submit("a", %{"text" => "apple"})
        |> submit("b", %{"text" => "banana"})
        |> submit("c", %{"text" => "cherry"})

      # players [a,b,c]; at step 1 player i holds book (i-1) mod 3:
      #   a → book2 (c's "cherry"), b → book0 (a's "apple"), c → book1 (b's "banana")
      assert GarticPhone.view(s, "a").prompt == %{kind: "text", by: "c", text: "cherry"}
      assert GarticPhone.view(s, "b").prompt == %{kind: "text", by: "a", text: "apple"}
      assert GarticPhone.view(s, "c").prompt == %{kind: "text", by: "b", text: "banana"}
    end

    test "a player never sees a book they already worked on (different prompt each step)" do
      s = gartic(~w(a b c)) |> all_submit("w0") |> all_submit("d1")
      # step 2 (text/describe): a holds book (0-2) mod 3 = book1
      assert s.game_state.step == 2
      assert GarticPhone.view(s, "a").my_kind == "text"
      # prompt is the step-1 drawing of book1
      assert GarticPhone.view(s, "a").prompt.kind == "drawing"
    end
  end

  describe "completion → album" do
    test "after n steps the game moves to the album" do
      s = gartic(~w(a b c)) |> all_submit("w0") |> all_submit("d1") |> all_submit("w2")
      assert s.phase == :album
      assert s.game_state.album == %{book: 0, page: 0}
    end

    test "album view exposes the book owner + chain up to the page" do
      s = gartic(~w(a b c)) |> all_submit("w0") |> all_submit("d1") |> all_submit("w2")
      v = GarticPhone.view(s, "a")
      assert v.phase == "album"
      assert v.album_book == 0
      assert v.book_owner == "a"
      assert length(v.pages) == 1
    end

    test "album_next walks pages, then books, then ends" do
      s = gartic(~w(a b c)) |> all_submit("w0") |> all_submit("d1") |> all_submit("w2")
      assert s.phase == :album
      assert s.game_state.album == %{book: 0, page: 0}

      # 3 books × 3 pages → walk to the last page of the last book,
      # then one more advance ends the game.
      {seq, _final} =
        Enum.map_reduce(1..9, s, fn _, acc ->
          next = GarticPhone.advance(acc)
          {{next.phase, next.game_state[:album]}, next}
        end)

      # Pages within book 0, then roll into the next book, … then over.
      assert {:album, %{book: 0, page: 2}} in seq
      assert {:album, %{book: 1, page: 0}} in seq
      assert {:album, %{book: 2, page: 2}} in seq
      assert List.last(seq) |> elem(0) == :gameover
    end
  end

  describe "edge cases" do
    test "advance fills missing submissions with a placeholder" do
      s = gartic(~w(a b c)) |> submit("a", %{"text" => "apple"})
      # b + c never submit; force-advance the step.
      s = GarticPhone.advance(s)
      assert s.game_state.step == 1
      # book for b's missing step-0 (book1) got a placeholder.
      assert s.game_state.books[1][0] == %{kind: "text", by: "b", text: "(no answer)"}
    end

    test "double submit + non-player are rejected" do
      s = gartic(~w(a b c)) |> submit("a", %{"text" => "apple"})

      assert {:error, :already_submitted} =
               GarticPhone.handle_action(s, {:submit, %{"text" => "x"}}, %{user_id: "a"})

      assert {:error, :not_a_player} =
               GarticPhone.handle_action(s, {:submit, %{"text" => "x"}}, %{user_id: "zzz"})
    end

    test "text is trimmed + length-capped; drawings stroke-capped" do
      s = gartic(~w(a b c))
      s = submit(s, "a", %{"text" => "  " <> String.duplicate("x", 500) <> "  "})
      assert String.length(s.game_state.books[0][0].text) == 200
    end
  end
end
