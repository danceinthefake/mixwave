defmodule Mixchamb.Retro.EphemeralStateTest do
  use ExUnit.Case, async: true

  alias Mixchamb.Retro.EphemeralState

  describe "cast_vote/3" do
    test "adds a vote during :voting" do
      s = EphemeralState.new("sess", :voting)
      assert {:ok, s2} = EphemeralState.cast_vote(s, "u1", "c1")
      assert MapSet.equal?(s2.votes["u1"], MapSet.new(["c1"]))
    end

    test "noop on re-voting same card" do
      s = EphemeralState.new("sess", :voting)
      {:ok, s2} = EphemeralState.cast_vote(s, "u1", "c1")
      assert {:noop, ^s2} = EphemeralState.cast_vote(s2, "u1", "c1")
    end

    test "enforces 3-vote cap per user" do
      s = EphemeralState.new("sess", :voting)
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c1")
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c2")
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c3")
      assert {:error, :vote_limit_reached} = EphemeralState.cast_vote(s, "u1", "c4")
    end

    test "noop outside :voting phase" do
      for phase <- [:setup, :brainstorm, :reveal, :discuss, :archived] do
        s = EphemeralState.new("sess", phase)
        assert {:noop, ^s} = EphemeralState.cast_vote(s, "u1", "c1")
      end
    end
  end

  describe "withdraw_vote/3" do
    test "drops a vote, prunes empty user key" do
      s = EphemeralState.new("sess", :voting)
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c1")
      assert {:ok, s2} = EphemeralState.withdraw_vote(s, "u1", "c1")
      refute Map.has_key?(s2.votes, "u1")
    end

    test "keeps user key when other votes remain" do
      s = EphemeralState.new("sess", :voting)
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c1")
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c2")
      {:ok, s2} = EphemeralState.withdraw_vote(s, "u1", "c1")
      assert MapSet.equal?(s2.votes["u1"], MapSet.new(["c2"]))
    end

    test "noop when not voted" do
      s = EphemeralState.new("sess", :voting)
      assert {:noop, ^s} = EphemeralState.withdraw_vote(s, "u1", "c1")
    end
  end

  describe "clear_user_votes/2" do
    test "drops all votes for a user on leave" do
      s = EphemeralState.new("sess", :voting)
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c1")
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c2")
      {:ok, s} = EphemeralState.cast_vote(s, "u2", "c1")
      {:ok, s2} = EphemeralState.clear_user_votes(s, "u1")
      refute Map.has_key?(s2.votes, "u1")
      assert MapSet.member?(s2.votes["u2"], "c1")
    end

    test "noop when user had no votes" do
      s = EphemeralState.new("sess", :voting)
      assert {:noop, ^s} = EphemeralState.clear_user_votes(s, "u-nobody")
    end
  end

  describe "tally/1" do
    test "aggregates per-card counts from per-user vote sets" do
      s = EphemeralState.new("sess", :voting)
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c1")
      {:ok, s} = EphemeralState.cast_vote(s, "u2", "c1")
      {:ok, s} = EphemeralState.cast_vote(s, "u3", "c1")
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c2")
      assert EphemeralState.tally(s) == %{"c1" => 3, "c2" => 1}
    end

    test "empty when no votes" do
      assert EphemeralState.tally(EphemeralState.new("sess")) == %{}
    end
  end

  describe "set_phase/2" do
    test "clears votes when exiting :voting" do
      s = EphemeralState.new("sess", :voting)
      {:ok, s} = EphemeralState.cast_vote(s, "u1", "c1")
      assert {:ok, s2} = EphemeralState.set_phase(s, :discuss)
      assert s2.votes == %{}
      assert s2.phase == :discuss
    end

    test "clears discussing focus when exiting :discuss" do
      s = %EphemeralState{phase: :discuss, discussing_card_id: "c1"}
      assert {:ok, s2} = EphemeralState.set_phase(s, :archived)
      assert s2.discussing_card_id == nil
      assert s2.phase == :archived
    end

    test "preserves state on non-clearing transitions" do
      s = EphemeralState.new("sess", :brainstorm)
      assert {:ok, s2} = EphemeralState.set_phase(s, :reveal)
      assert s2.phase == :reveal
    end
  end

  describe "set_discussing/2" do
    test "sets focus during :discuss" do
      s = %EphemeralState{phase: :discuss}
      assert {:ok, s2} = EphemeralState.set_discussing(s, "c1")
      assert s2.discussing_card_id == "c1"
    end

    test "clears focus with nil" do
      s = %EphemeralState{phase: :discuss, discussing_card_id: "c1"}
      assert {:ok, s2} = EphemeralState.set_discussing(s, nil)
      assert s2.discussing_card_id == nil
    end

    test "noop on same value" do
      s = %EphemeralState{phase: :discuss, discussing_card_id: "c1"}
      assert {:noop, ^s} = EphemeralState.set_discussing(s, "c1")
    end

    test "noop outside :discuss" do
      s = %EphemeralState{phase: :voting}
      assert {:noop, ^s} = EphemeralState.set_discussing(s, "c1")
    end
  end

  test "vote_cap/0 is 3 (spec §5)" do
    assert EphemeralState.vote_cap() == 3
  end

  describe "phase_from_string/1 + new/2 string input" do
    test "atom path still works" do
      s = EphemeralState.new("sess", :brainstorm)
      assert s.phase == :brainstorm
    end

    test "string input routes through phase_from_string" do
      for {str, atom} <- [
            {"setup", :setup},
            {"brainstorm", :brainstorm},
            {"reveal", :reveal},
            {"voting", :voting},
            {"discuss", :discuss},
            {"archived", :archived}
          ] do
        s = EphemeralState.new("sess", str)
        assert s.phase == atom, "expected #{inspect(str)} → #{inspect(atom)}"
      end
    end

    test "phase_from_string raises on unknown value" do
      assert_raise KeyError, fn ->
        EphemeralState.phase_from_string("nope")
      end
    end
  end
end
