defmodule Mixchamb.RateLimiter do
  @moduledoc """
  Tiny fixed-window counter backed by a public, named ETS table.

  Used to cap how often a single user can push note events to a
  chamber — a handful of clients hammering the LV `note` event can
  pump every other client's Tone.js graph and amplify the broadcast
  fan-out across all nodes, so we drop hits past the budget instead
  of forwarding them.

  Buckets are stored as `{key, window_start_ms, count}`. The first
  hit in a fresh window seeds the row; subsequent hits within the
  same window bump the count. When `now - window_start_ms` exceeds
  the window, the row is overwritten with a new window.

  No GenServer — every operation is an ETS lookup + insert. The
  table is created in `Mixchamb.Application.start/2`.

  Atomicity note: reads and writes are not transactional, so under
  contention two writers on the same key can momentarily exceed
  the budget by one. That's acceptable for an anti-flood guard.
  """

  @table :mixchamb_rate_limiter

  @doc "Name of the public ETS table."
  def table, do: @table

  @doc """
  Records a hit against `key`. Returns `:ok` if under budget,
  `:rate_limited` if the caller has already used `max` slots in the
  current window.

  `now` is injectable so tests can advance the clock without
  sleeping; production callers should omit it.
  """
  def hit(key, max, window_ms, now \\ System.monotonic_time(:millisecond))
      when is_integer(max) and is_integer(window_ms) and max > 0 and window_ms > 0 do
    case :ets.lookup(@table, key) do
      [{^key, window_start, count}] when now - window_start < window_ms ->
        if count >= max do
          :rate_limited
        else
          :ets.insert(@table, {key, window_start, count + 1})
          :ok
        end

      _ ->
        :ets.insert(@table, {key, now, 1})
        :ok
    end
  end

  @doc """
  Drops every bucket. Intended for tests — production callers
  should not need this.
  """
  def reset do
    :ets.delete_all_objects(@table)
    :ok
  end

  @doc """
  Drops a single bucket. Used by the admin UI to manually unblock
  a user whose window counter is stuck at the cap — e.g. a stale
  client that overshot, or a false-positive during a flood
  investigation. Idempotent: deleting a missing key is a no-op.
  """
  def reset_key(key) do
    :ets.delete(@table, key)
    :ok
  end

  @doc """
  Returns the current bucket for `key`, or `nil` if no hit has been
  recorded yet. Mostly useful for tests and introspection.
  """
  def peek(key) do
    case :ets.lookup(@table, key) do
      [{^key, window_start, count}] -> %{window_start: window_start, count: count}
      [] -> nil
    end
  end
end
