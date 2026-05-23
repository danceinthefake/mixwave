defmodule Mixchamb.Chambers.Sweeper do
  @moduledoc """
  Background sweeper that prunes idle and ghost chambers. Runs
  every 10 minutes under the application supervisor.

  Two paths each tick:

    * **Stale** — activated chambers whose `last_activity_at` is
      past the long threshold (#{4} hours). The conservative
      fallback for rooms that sat idle for hours.
    * **Ghost** — activated chambers whose `last_activity_at` is
      past the short threshold (#{30} min) AND whose per-slug
      GenServer is no longer in `Chambers.list_running/0`. The
      tighter pass catches BEAM-restart leftovers: once the
      GenServer dies, in-memory state is gone and the row is a
      tombstone (re-entering yields a fresh session per v4 §3.7).

  Mirrors `Mixchamb.Accounts.Sweeper`'s shape so the supervision
  tree + ops view treat them the same.

  Non-activated chambers (still in the 30-minute grace window) are
  owned by their per-chamber GenServer and aren't touched here —
  cleanup of those is the GenServer's responsibility (with the
  `delete_idle_since/1` fallback for rows whose GenServer died
  before grace could fire).
  """
  use GenServer
  require Logger

  alias Mixchamb.Chambers

  @sweep_interval :timer.minutes(10)
  @idle_threshold_hours 4
  @ghost_threshold_minutes 30

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Run a sweep right now (synchronous). Useful in tests and from
  the supervisor LiveView's "trigger now" button.
  """
  def sweep_now do
    GenServer.call(__MODULE__, :sweep_now)
  end

  @doc """
  Returns last-run + last-deleted + threshold metadata for the
  admin Sweepers tab.
  """
  def info do
    GenServer.call(__MODULE__, :info)
  end

  @impl true
  def init(_opts) do
    schedule_sweep()

    {:ok,
     %{
       last_run_at: nil,
       last_deleted: 0,
       last_stale_deleted: 0,
       last_ghost_deleted: 0
     }}
  end

  @impl true
  def handle_info(:sweep, state) do
    state = do_sweep(state)
    schedule_sweep()
    {:noreply, state}
  end

  @impl true
  def handle_call(:sweep_now, _from, state) do
    state = do_sweep(state)
    {:reply, {:ok, state.last_deleted}, state}
  end

  def handle_call(:info, _from, state) do
    {:reply,
     %{
       last_run_at: state.last_run_at,
       last_deleted: state.last_deleted,
       last_stale_deleted: state.last_stale_deleted,
       last_ghost_deleted: state.last_ghost_deleted,
       threshold_hours: @idle_threshold_hours,
       ghost_threshold_minutes: @ghost_threshold_minutes,
       interval_ms: @sweep_interval
     }, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end

  defp do_sweep(state) do
    now = DateTime.utc_now()

    stale_cutoff =
      now
      |> DateTime.add(-@idle_threshold_hours * 3600, :second)
      |> DateTime.truncate(:second)

    ghost_cutoff =
      now
      |> DateTime.add(-@ghost_threshold_minutes * 60, :second)
      |> DateTime.truncate(:second)

    # Snapshot of slugs whose GenServer is alive right now.
    # Anything past `ghost_cutoff` not in this set is a tombstone
    # safe to drop.
    running_slugs =
      Chambers.list_running()
      |> Enum.map(fn {slug, _pid} -> slug end)
      |> MapSet.new()

    stale = Chambers.delete_idle_since(stale_cutoff)
    ghost = Chambers.delete_ghost_chambers(ghost_cutoff, running_slugs)
    total = stale + ghost

    if total > 0 do
      Logger.info(
        "[chambers.sweeper] deleted #{total} chambers (#{stale} stale + #{ghost} ghost)"
      )
    end

    %{
      state
      | last_run_at: now,
        last_deleted: total,
        last_stale_deleted: stale,
        last_ghost_deleted: ghost
    }
  end
end
