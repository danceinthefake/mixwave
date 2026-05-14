defmodule MixwaveWeb.Admin.DashboardLive do
  @moduledoc """
  Admin landing page — at-a-glance counters for chambers, users,
  and live activity. Refreshes once per second so the dashboard
  reads as alive without a per-event subscription.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.{Accounts, Chambers}
  alias Mixwave.Telemetry.Counters
  alias MixwaveWeb.Admin.Layouts, as: AdminLayouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(1_000, :tick)

    {:ok,
     socket
     |> assign(:stats, snapshot())
     |> assign(:telemetry, Counters.snapshot())}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply,
     socket
     |> assign(:stats, snapshot())
     |> assign(:telemetry, Counters.snapshot())}
  end

  defp snapshot do
    running = Chambers.list_running()

    total_events =
      running
      |> Enum.map(fn {slug, _pid} ->
        case Mixwave.Chambers.Server.info(slug) do
          %{event_count: n} -> n
          _ -> 0
        end
      end)
      |> Enum.sum()

    %{
      chambers_total: Chambers.count_chambers(),
      chambers_activated: Chambers.count_activated_chambers(),
      chambers_running: length(running),
      users_total: Accounts.count_users(),
      users_active: Accounts.count_active_users(5),
      buffered_events: total_events
    }
  end

  defp top_instruments(notes_by_instrument, n) do
    notes_by_instrument
    |> Enum.sort_by(fn {_inst, count} -> count end, :desc)
    |> Enum.take(n)
  end

  defp format_uptime(ms) when ms < 60_000, do: "#{div(ms, 1_000)}s"
  defp format_uptime(ms) when ms < 3_600_000, do: "#{div(ms, 60_000)}m"
  defp format_uptime(ms) when ms < 86_400_000, do: "#{div(ms, 3_600_000)}h"
  defp format_uptime(ms), do: "#{div(ms, 86_400_000)}d"

  @impl true
  def render(assigns) do
    ~H"""
    <AdminLayouts.admin_shell
      current_view={__MODULE__}
      flash={@flash}
      banner={assigns[:banner]}
      draining?={assigns[:draining?] || false}
    >
      <.header>
        Dashboard
        <:subtitle>
          Live counters for the running app. Tick refresh every second.
        </:subtitle>
      </.header>

      <h2 class="mt-6 mb-2 text-xs uppercase tracking-wider text-muted-foreground font-display">
        Counts
      </h2>
      <div class="grid grid-cols-2 md:grid-cols-3 gap-3">
        <.stat label="Chambers — total" value={@stats.chambers_total} />
        <.stat
          label="Chambers — activated"
          value={@stats.chambers_activated}
          hint="someone other than the creator joined"
        />
        <.stat
          label="Chambers — running"
          value={@stats.chambers_running}
          hint="GenServer alive in BEAM"
        />
        <.stat label="Users — total" value={@stats.users_total} />
        <.stat
          label="Users — active 5 min"
          value={@stats.users_active}
          hint="last_active_at within 5 min"
        />
        <.stat
          label="Buffered events"
          value={@stats.buffered_events}
          hint="recent-events buffer across all chambers"
        />
      </div>

      <h2 class="mt-8 mb-2 text-xs uppercase tracking-wider text-muted-foreground font-display">
        Telemetry · since BEAM start ({format_uptime(@telemetry.uptime_ms)})
      </h2>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <.stat
          label="Notes / sec"
          value={@telemetry.notes_per_second}
          format={:rate}
          hint="rolling 10 s window"
        />
        <.stat
          label="Notes / min"
          value={@telemetry.notes_last_60s}
          hint="rolling 60 s window"
        />
        <.stat label="Notes — total" value={@telemetry.total_notes} />
        <.stat
          label="Notes — dropped"
          value={@telemetry.total_notes_dropped}
          hint="rate-limited at 20/sec/user"
        />
        <.stat
          label="Chambers created"
          value={@telemetry.total_created}
          hint="excluding system / Chaos"
        />
        <.stat
          label="Chambers deleted"
          value={@telemetry.total_deleted}
          hint="grace + sweeper + admin"
        />
        <.stat
          label="GenServer restarts"
          value={@telemetry.total_restarted}
          hint="chambers brought back by the supervisor"
        />
      </div>

      <h2 class="mt-8 mb-2 text-xs uppercase tracking-wider text-muted-foreground font-display">
        Notes by instrument
      </h2>
      <div
        :if={@telemetry.notes_by_instrument == %{}}
        class="rounded-lg border border-dashed bg-card/50 p-6 text-center text-sm text-muted-foreground"
      >
        No notes played yet. Open a chamber and hit a pad.
      </div>
      <div
        :if={@telemetry.notes_by_instrument != %{}}
        class="rounded-xl border bg-card p-4 space-y-2"
      >
        <% top = top_instruments(@telemetry.notes_by_instrument, 8) %>
        <% max = top |> Enum.map(&elem(&1, 1)) |> Enum.max(fn -> 1 end) %>
        <div :for={{inst, count} <- top} class="grid grid-cols-[6rem_1fr_4rem] gap-3 items-center">
          <div class="text-sm font-mono">{inst}</div>
          <div class="h-2 rounded-full bg-muted overflow-hidden">
            <div
              class="h-full bg-primary"
              style={"width: #{Float.round(count / max * 100, 1)}%"}
            >
            </div>
          </div>
          <div class="text-right tabular-nums text-sm">{count}</div>
        </div>
      </div>
    </AdminLayouts.admin_shell>
    """
  end

  attr :label, :string, required: true
  attr :value, :any, required: true
  attr :hint, :string, default: nil
  attr :format, :atom, default: :integer, values: [:integer, :rate]

  defp stat(assigns) do
    ~H"""
    <div class="rounded-xl border bg-card p-4">
      <div class="text-xs uppercase tracking-wider text-muted-foreground">{@label}</div>
      <div class="mt-1 text-3xl font-bold tabular-nums font-display">
        {format_value(@value, @format)}
      </div>
      <div :if={@hint} class="mt-1 text-[11px] text-muted-foreground">{@hint}</div>
    </div>
    """
  end

  defp format_value(v, :rate) when is_float(v), do: :erlang.float_to_binary(v, decimals: 1)
  defp format_value(v, :rate), do: "#{v}.0"
  defp format_value(v, _), do: v
end
