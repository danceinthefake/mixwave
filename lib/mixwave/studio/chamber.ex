defmodule Mixwave.Studio.Chamber do
  @moduledoc """
  One GenServer per chamber, registered by slug via
  `Mixwave.Studio.ChamberRegistry` and supervised by
  `Mixwave.Studio.ChamberSupervisor`.

  Holds the chamber's last N note events for join-time replay (the
  same buffer the old singleton `Studio.Room` used to hold for the
  global jam, just per-chamber now).

  `chamber_id` is the DB row's id — used by the lifecycle code to
  mark the chamber active or delete it. It's nilable so the
  GenServer can spin up before the persistence layer is wired in.

  The buffer is intentionally not persisted — when the GenServer
  restarts, the jam resumes empty.
  """
  use GenServer

  @max_recent 200

  ## Public API

  @doc """
  Returns the via-tuple for looking up a chamber's pid by slug.
  """
  def via(slug) when is_binary(slug) do
    {:via, Registry, {Mixwave.Studio.ChamberRegistry, slug}}
  end

  @doc """
  Starts the GenServer for a slug under the dynamic supervisor if
  it isn't already running. Idempotent — returns the existing pid
  if a chamber with this slug is already up.
  """
  def ensure_started(slug, chamber_id \\ nil) when is_binary(slug) do
    case DynamicSupervisor.start_child(
           Mixwave.Studio.ChamberSupervisor,
           {__MODULE__, {slug, chamber_id}}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      err -> err
    end
  end

  def start_link({slug, chamber_id}) do
    GenServer.start_link(__MODULE__, %{slug: slug, chamber_id: chamber_id}, name: via(slug))
  end

  def child_spec({slug, _chamber_id} = args) do
    %{
      id: {__MODULE__, slug},
      start: {__MODULE__, :start_link, [args]},
      restart: :temporary
    }
  end

  @doc """
  Records a note event in this chamber's buffer.
  """
  def record(slug, event), do: GenServer.cast(via(slug), {:record, event})

  @doc """
  Returns the buffered events oldest-first.
  """
  def recent_events(slug), do: GenServer.call(via(slug), :recent_events)

  @doc """
  Returns events from the last `seconds` seconds, oldest-first.
  """
  def recent_events_within(slug, seconds) do
    GenServer.call(via(slug), {:recent_events_within, seconds})
  end

  ## GenServer

  @impl true
  def init(state) do
    {:ok, Map.merge(state, %{events: [], count: 0})}
  end

  @impl true
  def handle_cast({:record, event}, state) do
    events = [event | state.events] |> Enum.take(@max_recent)
    {:noreply, %{state | events: events, count: state.count + 1}}
  end

  @impl true
  def handle_call(:recent_events, _from, state) do
    {:reply, Enum.reverse(state.events), state}
  end

  def handle_call({:recent_events_within, seconds}, _from, state) do
    cutoff = System.monotonic_time(:millisecond) - seconds * 1000

    events =
      state.events
      |> Enum.filter(&(&1.at >= cutoff))
      |> Enum.reverse()

    {:reply, events, state}
  end
end
