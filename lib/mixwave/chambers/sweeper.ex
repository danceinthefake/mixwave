defmodule Mixwave.Chambers.Sweeper do
  @moduledoc """
  Background sweeper that deletes activated chambers whose
  `last_activity_at` is more than 24 hours old. Runs hourly under
  the application supervisor.

  Mirrors `Mixwave.Accounts.Sweeper`'s shape so the supervision
  tree + ops view treat them the same.

  Non-activated chambers (still in the 30-minute grace window) are
  owned by their per-chamber GenServer and aren't touched here —
  cleanup of those is the GenServer's responsibility.
  """
  use GenServer
  require Logger

  alias Mixwave.Chambers

  @sweep_interval :timer.hours(1)
  @idle_threshold_hours 24

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
    {:ok, %{last_run_at: nil, last_deleted: 0}}
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
       threshold_hours: @idle_threshold_hours,
       interval_ms: @sweep_interval
     }, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end

  defp do_sweep(state) do
    cutoff =
      DateTime.utc_now()
      |> DateTime.add(-@idle_threshold_hours * 3600, :second)
      |> DateTime.truncate(:second)

    deleted = Chambers.delete_idle_since(cutoff)

    if deleted > 0 do
      Logger.info("[chambers.sweeper] deleted #{deleted} idle chambers")
    end

    %{state | last_run_at: DateTime.utc_now(), last_deleted: deleted}
  end
end
