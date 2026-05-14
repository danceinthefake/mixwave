defmodule MixwaveWeb.Admin.OpsLive do
  @moduledoc """
  Admin → Ops tab. Two things share this page:

    * **Broadcast banner** — admin types a message, picks a
      duration, and every connected LV shows it at the top of the
      page until it expires.
    * **Audit log** — append-only history of admin actions
      (kills, drains, broadcasts, sweeper runs, force-expires).

  Both back onto the `banners` and `admin_actions` tables.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.{Audit, Banners}
  alias MixwaveWeb.Admin.Layouts, as: AdminLayouts

  @durations [5, 15, 30, 60]

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mixwave.PubSub, Banners.topic())
      # Refresh "Just now"-style timestamps in the audit table.
      :timer.send_interval(5_000, :tick)
    end

    {:ok,
     socket
     |> assign(:actions, Audit.recent_actions(100))
     |> assign(:total_actions, Audit.count_actions())
     |> assign(:active_banner, Banners.current_banner())
     |> assign(:durations, @durations)
     |> assign(:default_duration, 15)
     |> assign(:message_input, "")}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply,
     socket
     |> assign(:active_banner, Banners.current_banner())
     |> assign(:actions, Audit.recent_actions(100))}
  end

  def handle_info({:banner_changed, banner}, socket) do
    {:noreply, assign(socket, :active_banner, banner)}
  end

  @impl true
  def handle_event("update_message", %{"value" => value}, socket) do
    {:noreply, assign(socket, :message_input, value)}
  end

  def handle_event(
        "broadcast",
        %{"message" => message, "duration" => duration},
        socket
      ) do
    duration = String.to_integer(duration)
    message = String.trim(message)

    cond do
      message == "" ->
        {:noreply, put_flash(socket, :error, "Message can't be empty.")}

      duration not in @durations ->
        {:noreply, put_flash(socket, :error, "Invalid duration.")}

      true ->
        admin = Application.get_env(:mixwave, :admin_user, "admin")

        case Banners.set_banner(message, duration, admin) do
          {:ok, banner} ->
            Audit.log("broadcast_banner", nil, %{
              message: message,
              duration_minutes: duration,
              banner_id: banner.id
            })

            {:noreply,
             socket
             |> assign(:active_banner, banner)
             |> assign(:message_input, "")
             |> assign(:actions, Audit.recent_actions(100))
             |> assign(:total_actions, Audit.count_actions())
             |> put_flash(:info, "Banner broadcast for #{duration} min.")}

          {:error, changeset} ->
            error =
              changeset.errors
              |> Enum.map(fn {f, {msg, _}} -> "#{f} #{msg}" end)
              |> Enum.join("; ")

            {:noreply, put_flash(socket, :error, "Couldn't broadcast: #{error}.")}
        end
    end
  end

  def handle_event("clear_banner", _params, socket) do
    case Banners.clear_banner() do
      {:ok, _} ->
        Audit.log("clear_banner", nil, %{})

        {:noreply,
         socket
         |> assign(:active_banner, nil)
         |> assign(:actions, Audit.recent_actions(100))
         |> assign(:total_actions, Audit.count_actions())
         |> put_flash(:info, "Banner cleared.")}

      {:error, _} ->
        {:noreply, put_flash(socket, :error, "Couldn't clear the banner.")}
    end
  end

  ## Render helpers

  defp time_ago(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      seconds < 5 -> "just now"
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp banner_expires_in(%{expires_at: expires_at}) do
    seconds = DateTime.diff(expires_at, DateTime.utc_now(), :second)

    cond do
      seconds <= 0 -> "expired"
      seconds < 60 -> "#{seconds}s"
      true -> "#{div(seconds, 60)}m"
    end
  end

  defp action_label(action) do
    action
    |> String.replace("_", " ")
    |> String.capitalize()
  end

  defp action_color("kill_chamber"), do: "bg-destructive/10 text-destructive"
  defp action_color("kill_process"), do: "bg-destructive/10 text-destructive"
  defp action_color("delete_chamber"), do: "bg-destructive/10 text-destructive"
  defp action_color("force_expire_user"), do: "bg-destructive/10 text-destructive"
  defp action_color("drain_node"), do: "bg-amber-500/10 text-amber-500"
  defp action_color("disconnect_node"), do: "bg-amber-500/10 text-amber-500"
  defp action_color("broadcast_banner"), do: "bg-primary/10 text-primary"
  defp action_color("clear_banner"), do: "bg-muted text-muted-foreground"
  defp action_color(_), do: "bg-muted text-muted-foreground"

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
        Ops
        <:subtitle>
          Broadcast a system banner and review every action the
          admin LV has performed.
        </:subtitle>
      </.header>

      <%!-- Broadcast form. --%>
      <section class="rounded-xl border bg-card p-5 space-y-4">
        <div>
          <h2 class="text-sm font-semibold font-display tracking-tight">Broadcast banner</h2>
          <p class="text-xs text-muted-foreground mt-1">
            Shows at the top of every connected page until it expires. Use sparingly — pre-deploys, schedule windows.
          </p>
        </div>

        <%!-- Active banner readout. --%>
        <div
          :if={@active_banner}
          class="rounded-md border border-primary/40 bg-primary/5 p-3 flex items-start gap-3"
        >
          <.icon name="hero-megaphone-mini" class="size-4 mt-0.5 text-primary" />
          <div class="flex-1 min-w-0 space-y-1">
            <div class="text-sm font-medium truncate">{@active_banner.message}</div>
            <div class="text-[11px] text-muted-foreground tabular-nums">
              expires in {banner_expires_in(@active_banner)} · by {@active_banner.inserted_by}
            </div>
          </div>
          <button
            type="button"
            phx-click="clear_banner"
            data-confirm="Clear the active banner right now?"
            class="rounded-md border bg-card hover:bg-destructive/10 hover:text-destructive px-2.5 py-1 text-xs cursor-pointer transition-colors"
          >
            Clear
          </button>
        </div>

        <form phx-submit="broadcast" class="space-y-3">
          <input
            type="text"
            name="message"
            value={@message_input}
            phx-change="update_message"
            maxlength="280"
            placeholder="Heads up — deploy in 5 minutes."
            class="w-full rounded-md border border-input bg-background px-3 py-2 text-sm outline-none focus:border-primary/60"
          />

          <div class="flex flex-wrap items-center gap-2">
            <span class="text-xs uppercase tracking-wider text-muted-foreground mr-1">
              Duration
            </span>
            <label
              :for={d <- @durations}
              class="cursor-pointer"
            >
              <input
                type="radio"
                name="duration"
                value={d}
                checked={d == @default_duration}
                class="peer sr-only"
              />
              <span class="inline-flex items-center px-3 py-1 text-xs rounded-md border bg-card peer-checked:bg-primary/15 peer-checked:text-primary peer-checked:border-primary/40 text-muted-foreground border-input transition-colors">
                {d} min
              </span>
            </label>

            <div class="flex-1"></div>

            <.button type="submit" variant="primary" disabled={String.trim(@message_input) == ""}>
              Broadcast
            </.button>
          </div>
        </form>
      </section>

      <%!-- Audit log table. --%>
      <section class="mt-6">
        <div class="flex items-baseline justify-between mb-3">
          <h2 class="text-sm font-semibold font-display tracking-tight">Audit log</h2>
          <span class="text-xs text-muted-foreground tabular-nums">
            showing {length(@actions)} of {@total_actions}
          </span>
        </div>

        <div
          :if={@actions == []}
          class="rounded-lg border border-dashed bg-card/50 p-6 text-center text-sm text-muted-foreground"
        >
          No actions logged yet. Kill a chamber, drain a node, or broadcast a banner to see entries here.
        </div>

        <div :if={@actions != []} class="rounded-xl border bg-card overflow-hidden">
          <div class="overflow-x-auto">
            <table class="w-full text-sm">
              <thead class="bg-muted/50 text-[11px] uppercase tracking-wider text-muted-foreground">
                <tr>
                  <th class="text-left px-4 py-2">When</th>
                  <th class="text-left px-4 py-2">Action</th>
                  <th class="text-left px-4 py-2">Target</th>
                  <th class="text-left px-4 py-2">Admin</th>
                  <th class="text-left px-4 py-2">Details</th>
                </tr>
              </thead>
              <tbody class="divide-y divide-border">
                <tr :for={a <- @actions} class="hover:bg-muted/30">
                  <td
                    class="px-4 py-2 text-xs text-muted-foreground tabular-nums whitespace-nowrap"
                    title={DateTime.to_string(a.inserted_at)}
                  >
                    {time_ago(a.inserted_at)}
                  </td>
                  <td class="px-4 py-2">
                    <span class={[
                      "inline-flex px-2 py-0.5 text-xs rounded-md font-medium",
                      action_color(a.action)
                    ]}>
                      {action_label(a.action)}
                    </span>
                  </td>
                  <td class="px-4 py-2 font-mono text-xs">
                    {a.target || "—"}
                  </td>
                  <td class="px-4 py-2 text-xs">{a.admin_user}</td>
                  <td class="px-4 py-2 font-mono text-xs text-muted-foreground max-w-md truncate">
                    {if map_size(a.metadata) == 0, do: "—", else: inspect(a.metadata)}
                  </td>
                </tr>
              </tbody>
            </table>
          </div>
        </div>
      </section>
    </AdminLayouts.admin_shell>
    """
  end
end
