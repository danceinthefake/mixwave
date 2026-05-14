defmodule MixwaveWeb.Admin.SystemLive do
  @moduledoc """
  Admin → System tab. Lists supervised singletons (Chambers
  supervisor + sweepers) and every running per-chamber GenServer,
  with kill buttons that send `:kill` to the pid; the dynamic
  supervisor restarts the chamber and the row briefly flashes red.

  Ported verbatim from the original /ops/supervisor LV — same data,
  wrapped in the admin shell instead of the bare app layout.
  """
  use MixwaveWeb, :live_view
  require Logger

  alias Mixwave.Chambers
  alias Mixwave.Chambers.Server, as: ChamberServer
  alias Mixwave.RestartWatcher
  alias MixwaveWeb.Admin.Layouts, as: AdminLayouts

  # Kept in sync with the matching keyframe in app.css.
  @flash_duration_ms 1_500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mixwave.PubSub, RestartWatcher.topic())
      :timer.send_interval(1_000, :tick)
    end

    {:ok,
     socket
     |> assign(:rows, RestartWatcher.snapshot())
     |> assign(:chambers, chamber_rows())}
  end

  @impl true
  def handle_info(:restarts_changed, socket) do
    {:noreply,
     socket
     |> assign(:rows, RestartWatcher.snapshot())
     |> assign(:chambers, chamber_rows())}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply,
     socket
     |> assign(:rows, RestartWatcher.snapshot())
     |> assign(:chambers, chamber_rows())}
  end

  @impl true
  def handle_event("kill", %{"module" => module}, socket) do
    mod = String.to_existing_atom(module)

    case Process.whereis(mod) do
      nil ->
        {:noreply, put_flash(socket, :error, "#{inspect(mod)} is not running.")}

      pid ->
        Logger.warning("[admin/system] kill issued: #{inspect(mod)} (pid #{inspect(pid)})")

        Mixwave.Audit.log_as(
          socket.assigns.current_admin,
          "kill_process",
          "module:#{inspect(mod)}",
          %{
            pid: inspect(pid)
          }
        )

        Process.exit(pid, :kill)
        {:noreply, put_flash(socket, :info, "Killed #{inspect(mod)} — supervisor will restart.")}
    end
  end

  def handle_event("kill_chamber", %{"slug" => slug}, socket) do
    case Registry.lookup(Mixwave.Chambers.Registry, slug) do
      [{pid, _}] ->
        Logger.warning("[admin/system] kill issued: chamber=#{slug} pid=#{inspect(pid)}")

        Mixwave.Audit.log_as(socket.assigns.current_admin, "kill_chamber", "chamber:#{slug}", %{
          pid: inspect(pid)
        })

        Process.exit(pid, :kill)

        {:noreply,
         put_flash(
           socket,
           :info,
           "Killed chamber #{slug} — Chambers.Supervisor will restart it."
         )}

      _ ->
        {:noreply, put_flash(socket, :error, "Chamber #{slug} is not running.")}
    end
  end

  defp chamber_rows do
    Chambers.list_running()
    |> Enum.map(fn {slug, pid} ->
      info = ChamberServer.info(slug)
      uptime_ms = (info && info.uptime_ms) || 0
      restart_count = Chambers.restart_count(slug)

      %{
        slug: slug,
        pid: pid,
        event_count: (info && info.event_count) || 0,
        uptime_ms: uptime_ms,
        restart_count: restart_count,
        flashing?: restart_count > 0 and uptime_ms < @flash_duration_ms
      }
    end)
    |> Enum.sort_by(& &1.slug)
  end

  defp format_memory(nil), do: "—"
  defp format_memory(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_memory(bytes) when bytes < 1_024 * 1_024, do: "#{div(bytes, 1_024)} KB"
  defp format_memory(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_pid(nil), do: "(down)"
  defp format_pid(pid), do: inspect(pid)

  defp format_uptime(ms) when ms < 1_000, do: "<1s"
  defp format_uptime(ms) when ms < 60_000, do: "#{div(ms, 1_000)}s"
  defp format_uptime(ms) when ms < 3_600_000, do: "#{div(ms, 60_000)}m"
  defp format_uptime(ms), do: "#{div(ms, 3_600_000)}h"

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
        System
        <:subtitle>
          Supervised processes that back the chamber runtime. Kill one
          and the supervisor restarts it; the chamber in another tab
          keeps running through the restart.
        </:subtitle>
      </.header>

      <div class="rounded-lg border bg-card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-xs uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2">Process</th>
              <th class="px-4 py-2">PID</th>
              <th class="px-4 py-2 text-right">Memory</th>
              <th class="px-4 py-2 text-right">Inbox</th>
              <th class="px-4 py-2 text-right">Restarts</th>
              <th class="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={row <- @rows} class="align-top">
              <td class="px-4 py-3">
                <div class="font-medium">{row.label}</div>
                <div class="text-xs text-muted-foreground">{row.description}</div>
              </td>
              <td class="px-4 py-3 font-mono text-xs">{format_pid(row.pid)}</td>
              <td class="px-4 py-3 text-right tabular-nums">
                {format_memory(row.info && row.info.memory)}
              </td>
              <td class="px-4 py-3 text-right tabular-nums">
                {(row.info && row.info.message_queue_len) || "—"}
              </td>
              <td class="px-4 py-3 text-right tabular-nums">
                <span class={[
                  "inline-flex items-center justify-center min-w-[2rem] px-2 py-0.5 rounded font-medium",
                  row.count > 0 && "bg-destructive/10 text-destructive",
                  row.count == 0 && "text-muted-foreground"
                ]}>
                  {row.count}
                </span>
              </td>
              <td class="px-4 py-3 text-right">
                <.button
                  variant="outline"
                  phx-click="kill"
                  phx-value-module={Atom.to_string(row.module)}
                  data-confirm={"Kill #{row.label}? The supervisor will restart it."}
                  class="text-destructive hover:bg-destructive/10 hover:text-destructive"
                >
                  Kill
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="mt-12 mb-4 flex items-end justify-between">
        <div>
          <h2 class="text-lg font-semibold tracking-tight font-display">
            Active chambers
          </h2>
          <p class="text-xs text-muted-foreground">
            One GenServer per chamber, supervised by Chambers.Supervisor.
            Killing a row drops the chamber's recent-events buffer; the
            supervisor restarts the GenServer in milliseconds and the
            jam in that chamber keeps playing through it.
          </p>
        </div>
        <div class="text-xs text-muted-foreground tabular-nums">
          {length(@chambers)} running
        </div>
      </div>

      <div
        :if={@chambers == []}
        class="rounded-lg border border-dashed bg-card/50 p-8 text-center text-sm text-muted-foreground"
      >
        No chambers running. Open one from the landing page to see it
        appear here in real time.
      </div>

      <div :if={@chambers != []} class="rounded-lg border bg-card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-xs uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2">Slug</th>
              <th class="px-4 py-2">PID</th>
              <th class="px-4 py-2 text-right">Events</th>
              <th class="px-4 py-2 text-right">Up</th>
              <th class="px-4 py-2 text-right">Restarts</th>
              <th class="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={c <- @chambers} class={["align-top", c.flashing? && "kill-flash"]}>
              <td class="px-4 py-3">
                <.link
                  navigate={~p"/chamber/#{c.slug}"}
                  class="font-mono text-xs font-medium hover:underline"
                >
                  {c.slug}
                </.link>
              </td>
              <td class="px-4 py-3 font-mono text-xs">{format_pid(c.pid)}</td>
              <td class="px-4 py-3 text-right tabular-nums">{c.event_count}</td>
              <td class="px-4 py-3 text-right tabular-nums text-muted-foreground">
                {format_uptime(c.uptime_ms)}
              </td>
              <td class="px-4 py-3 text-right tabular-nums">
                <span class={[
                  "inline-flex items-center justify-center min-w-[2rem] px-2 py-0.5 rounded font-medium",
                  c.restart_count > 0 && "bg-destructive/10 text-destructive",
                  c.restart_count == 0 && "text-muted-foreground"
                ]}>
                  {c.restart_count}
                </span>
              </td>
              <td class="px-4 py-3 text-right">
                <.button
                  variant="outline"
                  phx-click="kill_chamber"
                  phx-value-slug={c.slug}
                  data-confirm={"Kill chamber #{c.slug}? Recent-events buffer is dropped, then the supervisor restarts it."}
                  class="text-destructive hover:bg-destructive/10 hover:text-destructive"
                >
                  Kill
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <p class="mt-6 text-xs text-muted-foreground">
        Restart counts are per-process, persisted across kills until the
        BEAM restarts. Memory + inbox figures refresh once per second.
      </p>
    </AdminLayouts.admin_shell>
    """
  end
end
