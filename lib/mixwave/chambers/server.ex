defmodule Mixwave.Chambers.Server do
  @moduledoc """
  One GenServer per chamber, registered by slug via
  `Mixwave.Chambers.Registry` and supervised by
  `Mixwave.Chambers.Supervisor`.

  Holds the chamber's last N note events for join-time replay.
  Also owns the chamber lifecycle — the 5-minute grace-period
  self-check and the once-a-minute `last_activity_at` bump.

  `chamber_id` is the DB row's id — used by the lifecycle code to
  mark the chamber active or delete it. It's nilable so the
  GenServer can spin up before the persistence layer is wired in.

  The events buffer is intentionally not persisted — when the
  GenServer restarts, the jam resumes empty.
  """
  use GenServer

  @max_recent 200
  # Grace window during which the chamber must see a non-creator
  # join. If `activated_at` is still NULL when this elapses, the
  # GenServer deletes the chamber row and shuts itself down.
  @grace_period_ms 5 * 60 * 1000
  # How often the GenServer flushes the dirty flag to the DB by
  # bumping `last_activity_at`. Chosen for "rough enough that the
  # sweeper sees recent activity, cheap enough that it's not a
  # write per note even in busy chambers".
  @activity_bump_ms 60 * 1000

  ## Public API

  @doc """
  Returns the via-tuple for looking up a chamber's pid by slug.
  """
  def via(slug) when is_binary(slug) do
    {:via, Registry, {Mixwave.Chambers.Registry, slug}}
  end

  @doc """
  Starts the GenServer for a slug under the dynamic supervisor if
  it isn't already running. Idempotent — returns the existing pid
  if a chamber with this slug is already up.
  """
  def ensure_started(slug, chamber_id \\ nil) when is_binary(slug) do
    case DynamicSupervisor.start_child(
           Mixwave.Chambers.Supervisor,
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
    # Schedule the grace-period check. If a non-creator joins
    # before this fires, ChamberLive flips activated_at on the
    # row; when the message arrives we re-read the row and only
    # delete if it's still NULL.
    if state.chamber_id do
      Process.send_after(self(), :check_grace, @grace_period_ms)
      Process.send_after(self(), :bump_activity, @activity_bump_ms)
    end

    {:ok, Map.merge(state, %{events: [], count: 0, dirty?: false})}
  end

  @impl true
  def handle_cast({:record, event}, state) do
    events = [event | state.events] |> Enum.take(@max_recent)
    {:noreply, %{state | events: events, count: state.count + 1, dirty?: true}}
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

  @impl true
  def handle_info(:check_grace, %{chamber_id: chamber_id, slug: slug} = state) do
    case Mixwave.Chambers.find_by_id(chamber_id) do
      nil ->
        # Already deleted from DB out-of-band. Just terminate.
        {:stop, :normal, state}

      %{activated_at: nil} = chamber ->
        # Nobody but the creator showed up. Delete the row, tell
        # any subscribed LV to redirect, then shut down.
        Mixwave.Chambers.delete(chamber)

        Phoenix.PubSub.broadcast(
          Mixwave.PubSub,
          Mixwave.Chambers.topic(slug),
          {:chamber_closed, slug}
        )

        {:stop, :normal, state}

      _activated ->
        # A non-creator joined within the grace window — chamber
        # stays alive. Nothing more to schedule.
        {:noreply, state}
    end
  end

  def handle_info(:bump_activity, %{chamber_id: chamber_id, dirty?: dirty?} = state) do
    # If notes came in this minute, flush a single DB write to
    # update last_activity_at. If nothing happened, skip the write
    # — the sweeper will eventually decide this chamber is idle.
    if dirty? do
      case Mixwave.Chambers.find_by_id(chamber_id) do
        nil ->
          # Row deleted out-of-band (sweeper ran, or grace-period
          # delete fired). Stop the GenServer so we don't keep
          # trying to bump a non-existent row.
          {:stop, :normal, state}

        chamber ->
          Mixwave.Chambers.touch_activity(chamber)
          Process.send_after(self(), :bump_activity, @activity_bump_ms)
          {:noreply, %{state | dirty?: false}}
      end
    else
      Process.send_after(self(), :bump_activity, @activity_bump_ms)
      {:noreply, state}
    end
  end
end
