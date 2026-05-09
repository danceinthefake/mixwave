defmodule MixwaveWeb.Admin.SweepersLive do
  @moduledoc """
  Admin → Sweepers tab. Surfaces the two background sweepers
  (chambers + anonymous users), shows when each last ran and how
  many rows it deleted, and exposes a "Run now" button so an
  admin doesn't have to wait an hour for the next tick.
  """
  use MixwaveWeb, :live_view
  require Logger

  alias Mixwave.Accounts.Sweeper, as: AccountsSweeper
  alias Mixwave.Chambers.Sweeper, as: ChambersSweeper
  alias MixwaveWeb.Admin.Layouts, as: AdminLayouts

  @sweepers [
    %{
      key: "chambers",
      module: ChambersSweeper,
      label: "Chambers sweeper",
      description: "Deletes activated chambers idle past the threshold."
    },
    %{
      key: "users",
      module: AccountsSweeper,
      label: "Anonymous users sweeper",
      description: "Deletes anonymous users with no activity past the threshold."
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2_000, :tick)
    {:ok, assign(socket, :rows, snapshot())}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :rows, snapshot())}
  end

  @impl true
  def handle_event("run", %{"key" => key}, socket) do
    case Enum.find(@sweepers, &(&1.key == key)) do
      nil ->
        {:noreply, put_flash(socket, :error, "Unknown sweeper.")}

      sweeper ->
        Logger.warning("[admin/sweepers] manual sweep_now: #{sweeper.label}")
        {:ok, deleted} = sweeper.module.sweep_now()

        {:noreply,
         socket
         |> put_flash(:info, "#{sweeper.label}: deleted #{deleted}.")
         |> assign(:rows, snapshot())}
    end
  end

  defp snapshot do
    Enum.map(@sweepers, fn s ->
      info =
        try do
          s.module.info()
        catch
          :exit, _ -> nil
        end

      Map.merge(s, %{info: info})
    end)
  end

  defp time_ago(nil), do: "never"

  defp time_ago(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp format_interval(ms) when ms < 60_000, do: "#{div(ms, 1_000)}s"
  defp format_interval(ms) when ms < 3_600_000, do: "every #{div(ms, 60_000)}m"
  defp format_interval(ms), do: "every #{div(ms, 3_600_000)}h"

  @impl true
  def render(assigns) do
    ~H"""
    <AdminLayouts.admin_shell current_view={__MODULE__} flash={@flash}>
      <.header>
        Sweepers
        <:subtitle>
          Background processes that delete idle rows on a schedule.
          Run now triggers an out-of-band sweep without waiting for
          the next tick.
        </:subtitle>
      </.header>

      <div class="grid grid-cols-1 md:grid-cols-2 gap-4">
        <div :for={row <- @rows} class="rounded-xl border bg-card p-4">
          <div class="flex items-start justify-between gap-2">
            <div class="space-y-1 min-w-0">
              <div class="font-medium font-display">{row.label}</div>
              <div class="text-xs text-muted-foreground">{row.description}</div>
            </div>
            <span :if={row.info == nil} class="text-[10px] text-destructive uppercase tracking-wider">
              down
            </span>
          </div>

          <dl :if={row.info} class="mt-4 grid grid-cols-2 gap-y-2 text-sm">
            <dt class="text-xs uppercase tracking-wider text-muted-foreground">Last run</dt>
            <dd class="text-right tabular-nums">{time_ago(row.info.last_run_at)}</dd>

            <dt class="text-xs uppercase tracking-wider text-muted-foreground">Last deleted</dt>
            <dd class="text-right tabular-nums">{row.info.last_deleted}</dd>

            <dt class="text-xs uppercase tracking-wider text-muted-foreground">Threshold</dt>
            <dd class="text-right tabular-nums">{row.info.threshold_hours}h</dd>

            <dt class="text-xs uppercase tracking-wider text-muted-foreground">Schedule</dt>
            <dd class="text-right tabular-nums">{format_interval(row.info.interval_ms)}</dd>
          </dl>

          <div class="mt-4 flex justify-end">
            <.button
              :if={row.info}
              variant="outline"
              phx-click="run"
              phx-value-key={row.key}
              data-confirm={"Run #{row.label} now?"}
            >
              Run now
            </.button>
          </div>
        </div>
      </div>
    </AdminLayouts.admin_shell>
    """
  end
end
