defmodule MixwaveWeb.SupervisorLive do
  @moduledoc """
  Process supervisor view. Lists the supervised processes that
  back the studio, shows their PID, memory usage, message-queue
  length, and restart count, and exposes a Kill button per row.
  Kill sends `:kill` to the process; the supervisor restarts it,
  the counter ticks up.

  Updates push live via `RestartWatcher`'s PubSub topic; a 1-second
  polling tick keeps memory and queue numbers fresh between
  restarts.
  """
  use MixwaveWeb, :live_view
  require Logger

  alias Mixwave.RestartWatcher

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mixwave.PubSub, RestartWatcher.topic())
      # A slow tick keeps memory/queue numbers fresh between restarts.
      :timer.send_interval(1_000, :tick)
    end

    {:ok, assign(socket, :rows, RestartWatcher.snapshot())}
  end

  @impl true
  def handle_info(:restarts_changed, socket) do
    {:noreply, assign(socket, :rows, RestartWatcher.snapshot())}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :rows, RestartWatcher.snapshot())}
  end

  @impl true
  def handle_event("kill", %{"module" => module}, socket) do
    mod = String.to_existing_atom(module)

    case Process.whereis(mod) do
      nil ->
        {:noreply, put_flash(socket, :error, "#{inspect(mod)} is not running.")}

      pid ->
        Logger.warning(
          "[supervisor] kill issued from /ops/supervisor: #{inspect(mod)} (pid #{inspect(pid)})"
        )

        Process.exit(pid, :kill)
        {:noreply, put_flash(socket, :info, "Killed #{inspect(mod)} — supervisor will restart.")}
    end
  end

  ## Render helpers

  defp format_memory(nil), do: "—"
  defp format_memory(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_memory(bytes) when bytes < 1_024 * 1_024, do: "#{div(bytes, 1_024)} KB"
  defp format_memory(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_pid(nil), do: "(down)"
  defp format_pid(pid), do: inspect(pid)

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Supervisor
        <:subtitle>
          Supervised processes that back the studio. Kill one and the
          supervisor restarts it; the studio in another tab keeps
          running through the restart.
        </:subtitle>
        <:actions>
          <.link navigate={~p"/"} class="text-sm underline">← back to studio</.link>
        </:actions>
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
              <td class="px-4 py-3 font-mono text-xs">
                {format_pid(row.pid)}
              </td>
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

      <p class="mt-6 text-xs text-muted-foreground">
        Restart count is per-process, persisted across kills until the
        beam restarts. Memory + inbox figures refresh once per second.
      </p>
    </Layouts.app>
    """
  end
end
