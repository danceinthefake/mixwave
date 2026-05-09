defmodule MixwaveWeb.Admin.DashboardLive do
  @moduledoc """
  Admin landing page — at-a-glance counters for chambers, users,
  and live activity. Refreshes once per second so the dashboard
  reads as alive without a per-event subscription.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.{Accounts, Chambers}
  alias MixwaveWeb.Admin.Layouts, as: AdminLayouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(1_000, :tick)
    {:ok, assign(socket, :stats, snapshot())}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :stats, snapshot())}
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

  @impl true
  def render(assigns) do
    ~H"""
    <AdminLayouts.admin_shell current_view={__MODULE__} flash={@flash}>
      <.header>
        Dashboard
        <:subtitle>
          Live counters for the running app. Tick refresh every second.
        </:subtitle>
      </.header>

      <div class="grid grid-cols-2 md:grid-cols-3 gap-3 mt-4">
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
    </AdminLayouts.admin_shell>
    """
  end

  attr :label, :string, required: true
  attr :value, :integer, required: true
  attr :hint, :string, default: nil

  defp stat(assigns) do
    ~H"""
    <div class="rounded-xl border bg-card p-4">
      <div class="text-xs uppercase tracking-wider text-muted-foreground">{@label}</div>
      <div class="mt-1 text-3xl font-bold tabular-nums font-display">{@value}</div>
      <div :if={@hint} class="mt-1 text-[11px] text-muted-foreground">{@hint}</div>
    </div>
    """
  end
end
