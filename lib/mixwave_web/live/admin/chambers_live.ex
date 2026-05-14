defmodule MixwaveWeb.Admin.ChambersLive do
  @moduledoc """
  Admin → Chambers tab. Lists every chamber row with slug, title,
  kind, creator, lifecycle timestamps, presence count, and a force-
  delete action that bypasses the creator-only restriction.
  """
  use MixwaveWeb, :live_view
  require Logger

  alias Mixwave.Chambers
  alias Mixwave.Chambers.Server, as: ChamberServer
  alias Mixwave.RestartWatcher
  alias MixwaveWeb.Admin.Layouts, as: AdminLayouts
  alias MixwaveWeb.Presence

  # Kept in sync with the keyframe in app.css.
  @flash_duration_ms 1_500

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      # Subscribe so the kill-row flash appears the instant a
      # chamber GenServer restarts, not on the next 2 s tick.
      Phoenix.PubSub.subscribe(Mixwave.PubSub, RestartWatcher.topic())
      :timer.send_interval(2_000, :tick)
    end

    {:ok, assign(socket, :chambers, load())}
  end

  @impl true
  def handle_info(:tick, socket) do
    {:noreply, assign(socket, :chambers, load())}
  end

  def handle_info(:restarts_changed, socket) do
    {:noreply, assign(socket, :chambers, load())}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    case Mixwave.Repo.get(Mixwave.Chambers.Chamber, id) do
      nil ->
        {:noreply, put_flash(socket, :error, "Chamber not found.")}

      %{slug: slug} = chamber ->
        Logger.warning("[admin/chambers] force-delete: slug=#{slug} id=#{id}")

        Mixwave.Audit.log_as(socket.assigns.current_admin, "delete_chamber", "chamber:#{slug}", %{
          id: id
        })

        Chambers.delete(chamber)

        Phoenix.PubSub.broadcast(
          Mixwave.PubSub,
          Chambers.topic(slug),
          {:chamber_closed, slug}
        )

        {:noreply,
         socket
         |> put_flash(:info, "Deleted chamber #{slug}.")
         |> assign(:chambers, load())}
    end
  end

  defp load do
    running = Chambers.list_running() |> Enum.into(%{})

    Chambers.list_all()
    |> Enum.map(fn c ->
      running? = Map.has_key?(running, c.slug)
      restart_count = Chambers.restart_count(c.slug)

      uptime_ms =
        if running? do
          case ChamberServer.info(c.slug) do
            %{uptime_ms: ms} -> ms
            _ -> nil
          end
        end

      %{
        id: c.id,
        slug: c.slug,
        title: c.title,
        kind: c.kind,
        creator_user_id: c.creator_user_id,
        activated_at: c.activated_at,
        last_activity_at: c.last_activity_at,
        inserted_at: c.inserted_at,
        running?: running?,
        presence_count: presence_count(c.slug),
        # Flash if the GenServer behind this row restarted within
        # the animation window. Same predicate the System tab uses
        # so a chaos kill flashes both views in lockstep.
        flashing?:
          running? and restart_count > 0 and is_integer(uptime_ms) and
            uptime_ms < @flash_duration_ms
      }
    end)
  end

  defp presence_count(slug) do
    Presence.list("chamber:#{slug}:presence") |> map_size()
  end

  defp time_ago(nil), do: "—"

  defp time_ago(%DateTime{} = dt) do
    seconds = DateTime.diff(DateTime.utc_now(), dt, :second)

    cond do
      seconds < 60 -> "#{seconds}s ago"
      seconds < 3_600 -> "#{div(seconds, 60)}m ago"
      seconds < 86_400 -> "#{div(seconds, 3_600)}h ago"
      true -> "#{div(seconds, 86_400)}d ago"
    end
  end

  defp time_ago(%NaiveDateTime{} = ndt) do
    ndt |> DateTime.from_naive!("Etc/UTC") |> time_ago()
  end

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
        Chambers
        <:subtitle>
          Every chamber in the DB. Force-delete bypasses the
          creator-only check on /chamber/:slug and broadcasts a
          close so any LV in that chamber redirects to the landing
          page.
        </:subtitle>
      </.header>

      <div
        :if={@chambers == []}
        class="rounded-lg border border-dashed bg-card/50 p-8 text-center text-sm text-muted-foreground"
      >
        No chambers in the database yet.
      </div>

      <div :if={@chambers != []} class="rounded-lg border bg-card overflow-hidden overflow-x-auto">
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-xs uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2">Slug / Title</th>
              <th class="px-4 py-2">Kind</th>
              <th class="px-4 py-2">State</th>
              <th class="px-4 py-2 text-right">Present</th>
              <th class="px-4 py-2 text-right">Activity</th>
              <th class="px-4 py-2 text-right">Created</th>
              <th class="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={c <- @chambers} class={["align-top", c.flashing? && "kill-flash"]}>
              <td class="px-4 py-3">
                <div class="flex items-center gap-2">
                  <%!-- Slug now links to the admin drill-down. The
                       small ↗ link beside it still opens the
                       user-facing chamber view. --%>
                  <.link
                    navigate={~p"/admin/chambers/#{c.slug}"}
                    class="font-mono text-xs font-medium hover:underline"
                  >
                    {c.slug}
                  </.link>
                  <.link
                    navigate={~p"/chamber/#{c.slug}"}
                    class="text-[10px] text-muted-foreground hover:text-foreground"
                    title="Open the user-facing chamber"
                  >
                    ↗
                  </.link>
                </div>
                <div class="text-xs text-muted-foreground truncate max-w-[18rem]">
                  {c.title || "(no title)"}
                </div>
              </td>
              <td class="px-4 py-3">
                <span class="text-xs px-2 py-0.5 rounded bg-muted text-muted-foreground font-mono">
                  {c.kind}
                </span>
              </td>
              <td class="px-4 py-3 text-xs">
                <span :if={c.creator_user_id == nil} class="text-amber-600 dark:text-amber-400">
                  system
                </span>
                <span
                  :if={c.creator_user_id != nil and c.activated_at}
                  class="text-emerald-600 dark:text-emerald-400"
                >
                  active
                </span>
                <span
                  :if={c.creator_user_id != nil and is_nil(c.activated_at)}
                  class="text-muted-foreground"
                >
                  grace
                </span>
                <span
                  :if={not c.running?}
                  class="ml-1 text-[10px] uppercase tracking-wider text-muted-foreground"
                >
                  no GenServer
                </span>
              </td>
              <td class="px-4 py-3 text-right tabular-nums">{c.presence_count}</td>
              <td class="px-4 py-3 text-right text-xs text-muted-foreground">
                {time_ago(c.last_activity_at)}
              </td>
              <td class="px-4 py-3 text-right text-xs text-muted-foreground">
                {time_ago(c.inserted_at)}
              </td>
              <td class="px-4 py-3 text-right">
                <.button
                  variant="outline"
                  phx-click="delete"
                  phx-value-id={c.id}
                  data-confirm={"Force-delete chamber #{c.slug}? Connected users get kicked back to the landing page."}
                  class="text-destructive hover:bg-destructive/10 hover:text-destructive"
                >
                  Delete
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </AdminLayouts.admin_shell>
    """
  end
end
