defmodule MixchambWeb.Admin.FormatTest do
  use ExUnit.Case, async: true

  import MixchambWeb.Admin.Format

  describe "time_ago/1 + /2 with DateTime" do
    test "returns the default '—' when nil" do
      assert time_ago(nil) == "—"
    end

    test "returns the caller-supplied fallback when nil" do
      assert time_ago(nil, "never") == "never"
    end

    test "renders 'just now' for sub-5-second deltas" do
      now = DateTime.utc_now()
      assert time_ago(now) == "just now"
      assert time_ago(DateTime.add(now, -2, :second)) == "just now"
    end

    test "renders 'just now' for negative deltas (clock skew)" do
      future = DateTime.utc_now() |> DateTime.add(60, :second)
      assert time_ago(future) == "just now"
    end

    test "renders 'Ns ago' for sub-minute deltas (>= 5s)" do
      assert time_ago(DateTime.utc_now() |> DateTime.add(-30, :second)) =~ ~r/^\d+s ago$/
    end

    test "renders 'Nm ago' for sub-hour deltas" do
      result = time_ago(DateTime.utc_now() |> DateTime.add(-15, :minute))
      assert result == "15m ago"
    end

    test "renders 'Nh ago' for sub-day deltas" do
      result = time_ago(DateTime.utc_now() |> DateTime.add(-3, :hour))
      assert result == "3h ago"
    end

    test "renders 'Nd ago' past 24h" do
      result = time_ago(DateTime.utc_now() |> DateTime.add(-3 * 24, :hour))
      assert result == "3d ago"
    end

    test "accepts NaiveDateTime by converting to UTC" do
      ndt = DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.to_naive()
      assert time_ago(ndt) == "1h ago"
    end

    test "NaiveDateTime path also honours the fallback" do
      # NaiveDateTime never matches the nil clause; just confirm the
      # head delegates with the fallback so a future refactor doesn't
      # silently lose it.
      ndt = DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.to_naive()
      assert time_ago(ndt, "never") == "1h ago"
    end
  end

  describe "time_ago_ms/1 with monotonic-ms timestamps" do
    test "returns '—' for nil" do
      assert time_ago_ms(nil) == "—"
    end

    test "renders 'just now' for sub-5-second monotonic delta" do
      now = System.monotonic_time(:millisecond)
      assert time_ago_ms(now) == "just now"
      assert time_ago_ms(now - 2_000) == "just now"
    end

    test "renders 'Nm ago' for monotonic delta in minutes" do
      now = System.monotonic_time(:millisecond)
      assert time_ago_ms(now - 5 * 60 * 1_000) == "5m ago"
    end

    test "renders 'Nh ago' for monotonic delta in hours" do
      now = System.monotonic_time(:millisecond)
      assert time_ago_ms(now - 2 * 3_600 * 1_000) == "2h ago"
    end

    test "renders 'Nd ago' for monotonic delta in days" do
      now = System.monotonic_time(:millisecond)
      assert time_ago_ms(now - 3 * 86_400 * 1_000) == "3d ago"
    end
  end
end
