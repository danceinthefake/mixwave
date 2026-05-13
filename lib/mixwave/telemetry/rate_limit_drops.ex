defmodule Mixwave.Telemetry.RateLimitDrops do
  @moduledoc """
  Subscribes to the `[:mixwave, :chamber, :note_dropped]` telemetry
  event and rolls up per-`{user_id, slug}` counters in memory:

    * `count`         — lifetime drops for that pair (since BEAM start)
    * `last_drop_at`  — monotonic ms of the most recent drop

  Powers the admin Rate limits tab. Counters reset on restart;
  for "abuse over the last week" we'd need persistence, but
  the showcase target here is "spot someone hammering right now."

  Process-local state, no ETS — the trade-off is that the GenServer
  is the single writer, but at our 20 hits/sec/user budget the cast
  rate stays very low.
  """
  use GenServer

  @event [:mixwave, :chamber, :note_dropped]

  ## Public API

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc """
  Returns the snapshot the admin LV reads:

      %{
        total: integer,                          # lifetime across all users
        rows: [
          %{
            user_id: String.t(),
            slug: String.t(),
            count: integer,
            last_drop_at: integer | nil          # System.monotonic_time(:millisecond)
          },
          ...
        ]
      }

  Rows are returned newest-drop-first so the worst offender right
  now is at the top.
  """
  def snapshot, do: GenServer.call(__MODULE__, :snapshot)

  ## :telemetry handler

  def handle_event(@event, _measurements, metadata, _config) do
    GenServer.cast(__MODULE__, {:drop, metadata})
  end

  ## GenServer

  @impl true
  def init(_) do
    :telemetry.attach(
      {__MODULE__, @event},
      @event,
      &__MODULE__.handle_event/4,
      nil
    )

    {:ok, %{drops: %{}, total: 0}}
  end

  @impl true
  def handle_cast({:drop, %{slug: slug, user_id: user_id}}, state) do
    key = {user_id, slug}
    now = System.monotonic_time(:millisecond)

    drops =
      Map.update(state.drops, key, %{count: 1, last_drop_at: now}, fn existing ->
        %{count: existing.count + 1, last_drop_at: now}
      end)

    {:noreply, %{state | drops: drops, total: state.total + 1}}
  end

  def handle_cast({:drop, _other}, state), do: {:noreply, state}

  @impl true
  def handle_call(:snapshot, _from, state) do
    rows =
      state.drops
      |> Enum.map(fn {{user_id, slug}, %{count: c, last_drop_at: t}} ->
        %{user_id: user_id, slug: slug, count: c, last_drop_at: t}
      end)
      |> Enum.sort_by(& &1.last_drop_at, :desc)

    {:reply, %{total: state.total, rows: rows}, state}
  end
end
