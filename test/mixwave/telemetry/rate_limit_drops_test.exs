defmodule Mixwave.Telemetry.RateLimitDropsTest do
  use ExUnit.Case, async: false

  alias Mixwave.Telemetry.RateLimitDrops

  describe "snapshot/0" do
    test "returns the expected shape" do
      snap = RateLimitDrops.snapshot()
      assert is_map(snap)
      assert is_integer(snap.total)
      assert is_list(snap.rows)
    end
  end

  describe "drop events bump per-(user, slug) counters" do
    test "executing [:mixwave, :chamber, :note_dropped] increments the matching row" do
      before = RateLimitDrops.snapshot()

      :telemetry.execute(
        [:mixwave, :chamber, :note_dropped],
        %{count: 1},
        %{slug: "spam-room", user_id: "user-aaa"}
      )

      :telemetry.execute(
        [:mixwave, :chamber, :note_dropped],
        %{count: 1},
        %{slug: "spam-room", user_id: "user-aaa"}
      )

      # Synchronous call flushes any pending casts.
      after_snap = RateLimitDrops.snapshot()

      row = Enum.find(after_snap.rows, &(&1.user_id == "user-aaa" and &1.slug == "spam-room"))
      assert row
      assert row.count >= 2
      assert after_snap.total >= before.total + 2
    end

    test "different (user, slug) pairs maintain separate counters" do
      :telemetry.execute(
        [:mixwave, :chamber, :note_dropped],
        %{count: 1},
        %{slug: "room-a", user_id: "user-bbb"}
      )

      :telemetry.execute(
        [:mixwave, :chamber, :note_dropped],
        %{count: 1},
        %{slug: "room-b", user_id: "user-bbb"}
      )

      snap = RateLimitDrops.snapshot()

      assert Enum.any?(snap.rows, &(&1.user_id == "user-bbb" and &1.slug == "room-a"))
      assert Enum.any?(snap.rows, &(&1.user_id == "user-bbb" and &1.slug == "room-b"))
    end
  end
end
