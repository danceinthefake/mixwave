defmodule Mixwave.Telemetry.CountersTest do
  use ExUnit.Case, async: false

  alias Mixwave.Telemetry.Counters

  describe "snapshot/0" do
    test "returns the expected shape" do
      snap = Counters.snapshot()
      assert is_map(snap)

      for key <- ~w(
            total_notes total_notes_dropped total_created total_deleted
            total_restarted notes_last_60s notes_last_10s
            notes_per_second notes_by_instrument uptime_ms
          )a do
        assert Map.has_key?(snap, key), "missing key #{inspect(key)}"
      end

      assert is_float(snap.notes_per_second)
      assert is_map(snap.notes_by_instrument)
    end
  end

  describe "note events bump counters + per-instrument map" do
    test "executing the [:mixwave, :chamber, :note] event increments the counters" do
      before = Counters.snapshot()

      :telemetry.execute(
        [:mixwave, :chamber, :note],
        %{count: 1},
        %{slug: "x", instrument: "drums", style: "synth"}
      )

      :telemetry.execute(
        [:mixwave, :chamber, :note],
        %{count: 1},
        %{slug: "x", instrument: "kendang", style: "wood"}
      )

      # Round-trip a synchronous call so the cast handlers have run.
      _ = Counters.snapshot()
      after_snap = Counters.snapshot()

      assert after_snap.total_notes == before.total_notes + 2

      assert Map.get(after_snap.notes_by_instrument, "drums", 0) >=
               Map.get(before.notes_by_instrument, "drums", 0) + 1

      assert Map.get(after_snap.notes_by_instrument, "kendang", 0) >=
               Map.get(before.notes_by_instrument, "kendang", 0) + 1
    end
  end

  describe "lifecycle events" do
    test "created / deleted / restarted each bump their own counter" do
      before = Counters.snapshot()

      :telemetry.execute([:mixwave, :chamber, :created], %{count: 1}, %{slug: "a"})
      :telemetry.execute([:mixwave, :chamber, :deleted], %{count: 1}, %{slug: "a"})
      :telemetry.execute([:mixwave, :chamber, :restarted], %{count: 1}, %{slug: "a"})

      _ = Counters.snapshot()
      after_snap = Counters.snapshot()

      assert after_snap.total_created == before.total_created + 1
      assert after_snap.total_deleted == before.total_deleted + 1
      assert after_snap.total_restarted == before.total_restarted + 1
    end

    test "note_dropped bumps total_notes_dropped" do
      before = Counters.snapshot()

      :telemetry.execute([:mixwave, :chamber, :note_dropped], %{count: 1}, %{slug: "a"})

      _ = Counters.snapshot()
      after_snap = Counters.snapshot()

      assert after_snap.total_notes_dropped == before.total_notes_dropped + 1
    end
  end
end
