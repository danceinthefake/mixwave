defmodule Mixwave.RestartWatcher do
  @moduledoc """
  Tracks restart counts for a fixed set of supervised processes.

  `Supervisor` doesn't expose its restart history in a way callers
  can read, so we maintain our own counter by `Process.monitor/1`-ing
  each target. When a `:DOWN` message arrives we bump the counter
  and broadcast to PubSub so subscribers re-render without polling,
  then re-monitor the freshly-restarted PID.
  """
  use GenServer
  require Logger

  @topic "ops:restarts"

  # Processes we watch. Adding to this list automatically extends
  # the supervisor LiveView's table.
  @watched [
    {Mixwave.Chambers.Supervisor, "Chambers.Supervisor",
     "Spawns one GenServer per active chamber; holds each one's recent-events buffer."},
    {Mixwave.Accounts.Sweeper, "Accounts.Sweeper",
     "Deletes anonymous users idle for more than 24 hours."},
    {Mixwave.Chambers.Sweeper, "Chambers.Sweeper",
     "Deletes chambers idle for more than 24 hours."}
  ]

  def start_link(_opts), do: GenServer.start_link(__MODULE__, :ok, name: __MODULE__)

  @doc """
  Returns `[{module, label, description, %{pid, count, info}}]` for
  every watched process. Used by the LiveView for both the initial
  render and on every PubSub re-render.
  """
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  @doc """
  PubSub topic the LV subscribes to.
  """
  def topic, do: @topic

  ## GenServer

  @impl true
  def init(:ok) do
    state = %{
      counts: Map.new(@watched, fn {mod, _, _} -> {mod, 0} end),
      refs: %{}
    }

    {:ok, monitor_all(state)}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    items =
      Enum.map(@watched, fn {mod, label, desc} ->
        %{
          module: mod,
          label: label,
          description: desc,
          count: Map.get(state.counts, mod, 0),
          pid: Process.whereis(mod),
          info: process_info(mod)
        }
      end)

    {:reply, items, state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, pid, reason}, state) do
    case ref_to_module(state.refs, ref) do
      nil ->
        {:noreply, state}

      mod ->
        counts = Map.update!(state.counts, mod, &(&1 + 1))
        refs = Map.delete(state.refs, mod)

        Logger.warning(
          "[supervisor] #{inspect(mod)} (pid #{inspect(pid)}) DOWN: " <>
            "#{inspect(reason)} — restart count: #{counts[mod]}; supervisor will restart"
        )

        # The supervisor restarts within a few ms; re-monitor shortly.
        Process.send_after(self(), {:remonitor, mod}, 50)
        broadcast()
        {:noreply, %{state | counts: counts, refs: refs}}
    end
  end

  @impl true
  def handle_info({:remonitor, mod}, state) do
    case Process.whereis(mod) do
      nil ->
        # Not back yet; keep retrying.
        Process.send_after(self(), {:remonitor, mod}, 50)
        {:noreply, state}

      pid ->
        ref = Process.monitor(pid)
        Logger.info("[supervisor] #{inspect(mod)} restarted (pid #{inspect(pid)})")
        broadcast()
        {:noreply, %{state | refs: Map.put(state.refs, mod, ref)}}
    end
  end

  ## Helpers

  defp monitor_all(state) do
    refs =
      for {mod, _, _} <- @watched, into: %{} do
        case Process.whereis(mod) do
          nil -> {mod, nil}
          pid -> {mod, Process.monitor(pid)}
        end
      end

    %{state | refs: refs}
  end

  defp ref_to_module(refs, ref) do
    Enum.find_value(refs, fn
      {mod, ^ref} -> mod
      _ -> nil
    end)
  end

  defp process_info(mod) do
    case Process.whereis(mod) do
      nil ->
        nil

      pid ->
        case Process.info(pid, [:message_queue_len, :memory, :reductions]) do
          nil -> nil
          info -> Map.new(info)
        end
    end
  end

  defp broadcast, do: Phoenix.PubSub.broadcast(Mixwave.PubSub, @topic, :restarts_changed)
end
