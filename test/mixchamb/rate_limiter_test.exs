defmodule Mixchamb.RateLimiterTest do
  use ExUnit.Case, async: false

  alias Mixchamb.RateLimiter

  setup do
    # Each test starts with a clean table — buckets are global.
    RateLimiter.reset()
    :ok
  end

  describe "hit/4" do
    test "allows up to `max` hits within the window" do
      for _ <- 1..5 do
        assert :ok = RateLimiter.hit(:k, 5, 1_000, 100)
      end

      assert %{count: 5} = RateLimiter.peek(:k)
    end

    test "rejects the (max + 1)th hit in the same window" do
      Enum.each(1..5, fn _ -> RateLimiter.hit(:k, 5, 1_000, 100) end)
      assert :rate_limited = RateLimiter.hit(:k, 5, 1_000, 100)
    end

    test "starts a fresh window once the previous one expires" do
      Enum.each(1..5, fn _ -> RateLimiter.hit(:k, 5, 1_000, 100) end)
      assert :rate_limited = RateLimiter.hit(:k, 5, 1_000, 100)

      # 1_100 ms later — past the 1 s window.
      assert :ok = RateLimiter.hit(:k, 5, 1_000, 1_200)
      assert %{count: 1, window_start: 1_200} = RateLimiter.peek(:k)
    end

    test "buckets are independent per key" do
      Enum.each(1..5, fn _ -> RateLimiter.hit(:a, 5, 1_000, 100) end)

      # Key :a is full; :b is empty.
      assert :rate_limited = RateLimiter.hit(:a, 5, 1_000, 100)
      assert :ok = RateLimiter.hit(:b, 5, 1_000, 100)
    end
  end

  describe "peek/1 and reset/0" do
    test "peek returns nil before any hit" do
      assert RateLimiter.peek(:never_hit) == nil
    end

    test "reset clears every bucket" do
      RateLimiter.hit(:a, 5, 1_000, 100)
      RateLimiter.hit(:b, 5, 1_000, 100)

      :ok = RateLimiter.reset()

      assert RateLimiter.peek(:a) == nil
      assert RateLimiter.peek(:b) == nil
    end

    test "reset_key/1 clears one bucket and leaves the others" do
      RateLimiter.hit(:a, 5, 1_000, 100)
      RateLimiter.hit(:b, 5, 1_000, 100)

      :ok = RateLimiter.reset_key(:a)

      assert RateLimiter.peek(:a) == nil
      assert %{count: 1} = RateLimiter.peek(:b)
    end

    test "reset_key/1 is idempotent on a missing key" do
      assert :ok = RateLimiter.reset_key(:never_existed)
    end
  end
end
