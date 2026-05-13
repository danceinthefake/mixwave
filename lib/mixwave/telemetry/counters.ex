defmodule Mixwave.Telemetry.Counters do
  @moduledoc """
  Subscribes to mixwave's custom telemetry events and maintains
  in-memory counters the admin Dashboard reads. Lives at the top
  of the supervision tree so it survives chamber and sweeper
  restarts; counters are intentionally process-local — they reset
  when the BEAM restarts.

  Three kinds of measurement come out of `snapshot/0`:

    * lifetime totals (notes, chambers created/deleted/restarted)
    * 60-second / 10-second windows so the LV can show "notes per
      minute" and "notes per second" rates
    * per-instrument breakdown for a "what's being played most"
      view

  The 60-second history is kept as a queue of monotonic timestamps
  (one per note); we trim the queue head past the 60 s cutoff
  before answering snapshot requests, so memory stays bounded by
  the chamber's note rate × 60 s — at the kind of jam intensity
  we're optimising for (≤30 notes/sec) this is at most a few
  thousand integers.
  """
  use GenServer

  @events [
    [:mixwave, :chamber, :note],
    [:mixwave, :chamber, :note_dropped],
    [:mixwave, :chamber, :created],
    [:mixwave, :chamber, :deleted],
    [:mixwave, :chamber, :restarted]
  ]

  @history_window_ms 60_000

  ## Public API

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Returns a snapshot map for the admin Dashboard. See moduledoc
  for the shape.
  """
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  ## :telemetry callbacks
  ##
  ## Each handler casts to the GenServer so the publishing
  ## process (a chamber or controller) never blocks on
  ## counter bookkeeping.

  def handle_event([:mixwave, :chamber, :note], _measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:note, metadata})
  end

  def handle_event([:mixwave, :chamber, :note_dropped], _, _, _) do
    GenServer.cast(__MODULE__, :note_dropped)
  end

  def handle_event([:mixwave, :chamber, :created], _, _, _) do
    GenServer.cast(__MODULE__, :created)
  end

  def handle_event([:mixwave, :chamber, :deleted], _, _, _) do
    GenServer.cast(__MODULE__, :deleted)
  end

  def handle_event([:mixwave, :chamber, :restarted], _, _, _) do
    GenServer.cast(__MODULE__, :restarted)
  end

  ## GenServer

  @impl true
  def init(_) do
    Enum.each(@events, fn event ->
      :telemetry.attach(
        {__MODULE__, event},
        event,
        &__MODULE__.handle_event/4,
        nil
      )
    end)

    state = %{
      counters: %{notes: 0, notes_dropped: 0, created: 0, deleted: 0, restarted: 0},
      notes_by_instrument: %{},
      notes_history: :queue.new(),
      started_at: System.monotonic_time(:millisecond)
    }

    {:ok, state}
  end

  @impl true
  def handle_cast({:note, metadata}, state) do
    instrument = metadata[:instrument] || metadata["instrument"] || "unknown"
    now = System.monotonic_time(:millisecond)

    state =
      state
      |> update_in([:counters, :notes], &(&1 + 1))
      |> update_in([:notes_by_instrument, Access.key(instrument, 0)], &(&1 + 1))
      |> Map.update!(:notes_history, &:queue.in(now, &1))

    {:noreply, state}
  end

  def handle_cast(:note_dropped, state) do
    {:noreply, update_in(state, [:counters, :notes_dropped], &(&1 + 1))}
  end

  def handle_cast(:created, state) do
    {:noreply, update_in(state, [:counters, :created], &(&1 + 1))}
  end

  def handle_cast(:deleted, state) do
    {:noreply, update_in(state, [:counters, :deleted], &(&1 + 1))}
  end

  def handle_cast(:restarted, state) do
    {:noreply, update_in(state, [:counters, :restarted], &(&1 + 1))}
  end

  @impl true
  def handle_call(:snapshot, _from, state) do
    now = System.monotonic_time(:millisecond)
    history = trim_old(state.notes_history, now - @history_window_ms)
    notes_last_60s = :queue.len(history)

    notes_last_10s =
      history
      |> :queue.to_list()
      |> Enum.count(fn t -> t >= now - 10_000 end)

    snapshot = %{
      total_notes: state.counters.notes,
      total_notes_dropped: state.counters.notes_dropped,
      total_created: state.counters.created,
      total_deleted: state.counters.deleted,
      total_restarted: state.counters.restarted,
      notes_last_60s: notes_last_60s,
      notes_last_10s: notes_last_10s,
      # Float so the dashboard can show "0.7 / sec" rather than
      # snapping to integers at low rates.
      notes_per_second: notes_last_10s / 10.0,
      notes_by_instrument: state.notes_by_instrument,
      uptime_ms: now - state.started_at
    }

    {:reply, snapshot, %{state | notes_history: history}}
  end

  defp trim_old(queue, cutoff_ms) do
    case :queue.peek(queue) do
      :empty ->
        queue

      {:value, t} when t < cutoff_ms ->
        {_, q} = :queue.out(queue)
        trim_old(q, cutoff_ms)

      _ ->
        queue
    end
  end
end
