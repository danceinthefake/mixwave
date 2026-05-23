defmodule Mixchamb.Chambers.PokerSessionTest do
  use ExUnit.Case, async: true

  alias Mixchamb.Chambers.PokerSession

  describe "new/1" do
    test "defaults to fibonacci, voting, no votes, round 1" do
      s = PokerSession.new()
      assert s.status == :voting
      assert s.deck == :fibonacci
      assert s.votes == %{}
      assert s.round == 1
      assert is_nil(s.story)
    end

    test "honors a non-default deck" do
      assert %{deck: :tshirt} = PokerSession.new(:tshirt)
    end
  end

  describe "cards_for/1" do
    test "returns the right values per deck, including ? and ☕ where applicable" do
      assert PokerSession.cards_for(:fibonacci) == ~w(1 2 3 5 8 13 21 ? ☕)
      assert PokerSession.cards_for(:tshirt) == ~w(XS S M L XL ?)
      assert "☕" in PokerSession.cards_for(:pow2)
      assert "100" in PokerSession.cards_for(:modified_fibonacci)
    end
  end

  describe "cast_vote/3" do
    test "records the vote during :voting" do
      s = PokerSession.new()
      assert {:ok, updated} = PokerSession.cast_vote(s, "alice", "5")
      assert updated.votes == %{"alice" => "5"}
    end

    test "is idempotent — same card by same user is a no-op" do
      s = %{PokerSession.new() | votes: %{"alice" => "5"}}
      assert {:noop, ^s} = PokerSession.cast_vote(s, "alice", "5")
    end

    test "lets a user change their vote during :voting" do
      s = %{PokerSession.new() | votes: %{"alice" => "5"}}
      assert {:ok, updated} = PokerSession.cast_vote(s, "alice", "8")
      assert updated.votes == %{"alice" => "8"}
    end

    test "rejects a card that isn't in the active deck" do
      s = PokerSession.new(:tshirt)
      assert {:error, :invalid_card} = PokerSession.cast_vote(s, "alice", "13")
    end

    test "is a no-op during :revealed" do
      s = %{PokerSession.new() | status: :revealed}
      assert {:noop, ^s} = PokerSession.cast_vote(s, "alice", "5")
    end
  end

  describe "withdraw_vote/2" do
    test "drops a vote during :voting" do
      s = %{PokerSession.new() | votes: %{"alice" => "5", "bob" => "8"}}
      assert {:ok, updated} = PokerSession.withdraw_vote(s, "alice")
      assert updated.votes == %{"bob" => "8"}
    end

    test "is a no-op when the user hasn't voted" do
      s = PokerSession.new()
      assert {:noop, ^s} = PokerSession.withdraw_vote(s, "alice")
    end

    test "is a no-op during :revealed" do
      s = %{PokerSession.new() | status: :revealed, votes: %{"alice" => "5"}}
      assert {:noop, ^s} = PokerSession.withdraw_vote(s, "alice")
    end
  end

  describe "reveal/1" do
    test "flips :voting to :revealed, preserving votes" do
      s = %{PokerSession.new() | votes: %{"alice" => "5"}}
      assert {:ok, updated} = PokerSession.reveal(s)
      assert updated.status == :revealed
      assert updated.votes == %{"alice" => "5"}
    end

    test "reveal with zero votes is allowed (no gate)" do
      s = PokerSession.new()
      assert {:ok, %{status: :revealed, votes: %{}}} = PokerSession.reveal(s)
    end

    test "re-revealing is a no-op" do
      s = %{PokerSession.new() | status: :revealed}
      assert {:noop, ^s} = PokerSession.reveal(s)
    end
  end

  describe "revote/1" do
    test "from :revealed clears votes and flips to :voting, keeping round + story + deck" do
      s = %{
        PokerSession.new(:tshirt)
        | status: :revealed,
          votes: %{"alice" => "M", "bob" => "L"},
          round: 4,
          story: "Carry over"
      }

      assert {:ok, updated} = PokerSession.revote(s)
      assert updated.status == :voting
      assert updated.votes == %{}
      assert updated.round == 4
      assert updated.story == "Carry over"
      assert updated.deck == :tshirt
    end

    test "from :voting with votes also clears (host can restart mid-round)" do
      s = %{PokerSession.new() | votes: %{"alice" => "3"}}
      assert {:ok, %{votes: %{}, status: :voting}} = PokerSession.revote(s)
    end

    test "no-op when already :voting with empty votes" do
      s = PokerSession.new()
      assert {:noop, ^s} = PokerSession.revote(s)
    end
  end

  describe "next_round/2" do
    test "clears votes, increments round, returns to :voting" do
      s = %{
        PokerSession.new()
        | status: :revealed,
          votes: %{"alice" => "5", "bob" => "8"},
          round: 3,
          story: "Add dark mode"
      }

      assert {:ok, updated} = PokerSession.next_round(s)
      assert updated.status == :voting
      assert updated.votes == %{}
      assert updated.round == 4
      # Story carries over unless explicitly replaced.
      assert updated.story == "Add dark mode"
    end

    test "swaps the story when :story is passed" do
      s = %{PokerSession.new() | story: "Old"}
      assert {:ok, %{story: "New"}} = PokerSession.next_round(s, story: "New")
    end

    test "pushes the finished round onto history, newest-first" do
      s = %{
        PokerSession.new()
        | status: :revealed,
          votes: %{"alice" => "5", "bob" => "8"},
          round: 1,
          story: "Add dark mode"
      }

      assert {:ok, after_first} = PokerSession.next_round(s, story: "Migration")
      assert [entry] = after_first.history
      assert entry.round == 1
      assert entry.story == "Add dark mode"
      assert entry.deck == :fibonacci
      assert entry.votes == %{"alice" => "5", "bob" => "8"}

      # Second next_round prepends — newest first.
      after_second =
        elem(
          PokerSession.next_round(%{after_first | votes: %{"alice" => "13"}, status: :revealed}),
          1
        )

      assert [%{round: 2, story: "Migration"}, %{round: 1, story: "Add dark mode"}] =
               after_second.history
    end

    test "skips history when the round had no votes and no story" do
      # Host clicks Next Round on an empty placeholder — nothing to remember.
      s = PokerSession.new()
      assert {:ok, updated} = PokerSession.next_round(s)
      assert updated.history == []
    end

    test "keeps the round in history when the host set a story but no votes came in" do
      s = %{PokerSession.new() | story: "Discussed offline", round: 2}
      assert {:ok, updated} = PokerSession.next_round(s)
      assert [%{round: 2, story: "Discussed offline", votes: %{}}] = updated.history
    end

    test "pops the queue head into :story when no explicit :story opt is passed" do
      s = %{PokerSession.new() | story: "Current", queue: ["Next one", "After that"]}
      assert {:ok, updated} = PokerSession.next_round(s)
      assert updated.story == "Next one"
      assert updated.queue == ["After that"]
    end

    test "explicit :story opt wins over the queue head" do
      s = %{PokerSession.new() | story: "Current", queue: ["Queued"]}
      assert {:ok, updated} = PokerSession.next_round(s, story: "Override")
      assert updated.story == "Override"
      # Queue is left alone — the host's explicit edit said "use
      # this, not the queue", so the queue head is still there to
      # use next time.
      assert updated.queue == ["Queued"]
    end

    test "carries over the current story when the queue is empty" do
      s = %{PokerSession.new() | story: "Carry me", queue: []}
      assert {:ok, updated} = PokerSession.next_round(s)
      assert updated.story == "Carry me"
    end
  end

  describe "set_queue/2" do
    test "replaces the queue with the trimmed non-blank lines" do
      s = PokerSession.new()
      assert {:ok, updated} = PokerSession.set_queue(s, ["  one  ", "", "two", "   "])
      assert updated.queue == ["one", "two"]
    end

    test "no-op when the queue is unchanged" do
      s = %{PokerSession.new() | queue: ["already", "here"]}
      assert {:noop, ^s} = PokerSession.set_queue(s, ["already", "here"])
    end

    test "preserves duplicates (intentional re-estimation)" do
      s = PokerSession.new()
      assert {:ok, updated} = PokerSession.set_queue(s, ["Story X", "Story X"])
      assert updated.queue == ["Story X", "Story X"]
    end

    test "rejects non-list input" do
      s = PokerSession.new()
      assert {:error, :invalid_queue} = PokerSession.set_queue(s, "not a list")
    end

    test "caps the queue at the documented max" do
      lines = Enum.map(1..80, &"Story #{&1}")
      s = PokerSession.new()
      assert {:ok, updated} = PokerSession.set_queue(s, lines)
      assert length(updated.queue) == 50
      assert hd(updated.queue) == "Story 1"
    end
  end

  describe "set_story/2" do
    test "updates the story line" do
      s = PokerSession.new()
      assert {:ok, %{story: "Estimate the migration"}} =
               PokerSession.set_story(s, "Estimate the migration")
    end

    test "nil clears the story" do
      s = %{PokerSession.new() | story: "Old"}
      assert {:ok, %{story: nil}} = PokerSession.set_story(s, nil)
    end

    test "no-op when the story is unchanged" do
      s = %{PokerSession.new() | story: "Same"}
      assert {:noop, ^s} = PokerSession.set_story(s, "Same")
    end
  end

  describe "set_deck/2" do
    test "switches deck when no votes are cast" do
      s = PokerSession.new()
      assert {:ok, %{deck: :tshirt}} = PokerSession.set_deck(s, :tshirt)
    end

    test "rejects the switch when votes are in progress" do
      s = %{PokerSession.new() | votes: %{"alice" => "5"}}
      assert {:error, :votes_in_progress} = PokerSession.set_deck(s, :tshirt)
    end

    test "no-op when switching to the same deck" do
      s = PokerSession.new(:pow2)
      assert {:noop, ^s} = PokerSession.set_deck(s, :pow2)
    end

    test "rejects an unknown deck" do
      s = PokerSession.new()
      assert {:error, :invalid_deck} = PokerSession.set_deck(s, :no_such_deck)
    end
  end
end
