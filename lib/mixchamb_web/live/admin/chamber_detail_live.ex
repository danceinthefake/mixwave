defmodule MixchambWeb.Admin.ChamberDetailLive do
  @moduledoc """
  Admin → Chambers → :slug drill-down.

  Subscribes to the chamber's PubSub + presence topics so every
  note hit and join/leave updates the page live. Combines DB
  rows (Chambers schema + recorded event count) with runtime
  state from the per-slug Server (`event_count`, `uptime_ms`)
  and the supervision-tree restart counter.

  Sidebar highlights the Chambers tab via the `current_view`
  override below — this LV piggy-backs on that nav entry.
  """
  use MixchambWeb, :live_view
  require Logger

  alias Mixchamb.Chambers
  alias Mixchamb.Chambers.Server, as: ChamberServer
  alias MixchambWeb.Admin.Layouts, as: AdminLayouts
  alias MixchambWeb.Presence
  import MixchambWeb.Admin.Format, only: [time_ago: 1]

  @recent_notes_max 20

  @impl true
  def mount(%{"slug" => slug}, _session, socket) do
    case Chambers.find_by_slug(slug) do
      nil ->
        {:ok,
         socket
         |> put_flash(:error, "Chamber not found.")
         |> push_navigate(to: ~p"/admin/chambers")}

      chamber ->
        if connected?(socket) do
          Chambers.subscribe(slug)
          Phoenix.PubSub.subscribe(Mixchamb.PubSub, presence_topic(slug))
          # Refresh server info / recorded count + age out "Xs ago"
          # labels every 2 s.
          :timer.send_interval(2_000, :tick)
        end

        {:ok,
         socket
         |> assign(:chamber, chamber)
         |> assign(:slug, slug)
         |> assign(:server_info, ChamberServer.info(slug))
         |> assign(:restart_count, Chambers.restart_count(slug))
         |> assign(:recorded_count, Chambers.recorded_event_count(chamber.id))
         |> assign(:presences, Presence.list(presence_topic(slug)))
         |> assign(:recent_notes, [])
         |> assign(:page_title, "Chamber · #{slug}")}
    end
  end

  @impl true
  def handle_info(:tick, socket) do
    chamber = socket.assigns.chamber

    {:noreply,
     socket
     |> assign(:server_info, ChamberServer.info(socket.assigns.slug))
     |> assign(:restart_count, Chambers.restart_count(socket.assigns.slug))
     |> assign(:recorded_count, Chambers.recorded_event_count(chamber.id))}
  end

  def handle_info({:chamber_note, event}, socket) do
    # Prepend + cap so the list reads newest-first without unbounded
    # growth. The note feed is a UI-only stream; persistence already
    # happens through the chamber's GenServer.
    notes = [event | socket.assigns.recent_notes] |> Enum.take(@recent_notes_max)
    {:noreply, assign(socket, :recent_notes, notes)}
  end

  def handle_info(%Phoenix.Socket.Broadcast{event: "presence_diff"}, socket) do
    {:noreply, assign(socket, :presences, Presence.list(presence_topic(socket.assigns.slug)))}
  end

  # Chamber row update broadcast (title, kind, recording flag).
  def handle_info({:chamber_updated, updated}, socket) do
    {:noreply, assign(socket, :chamber, updated)}
  end

  def handle_info({:chamber_closed, _slug}, socket) do
    {:noreply,
     socket
     |> put_flash(:info, "Chamber closed.")
     |> push_navigate(to: ~p"/admin/chambers")}
  end

  @impl true
  def handle_event("delete_chamber", _params, socket) do
    chamber = socket.assigns.chamber

    Mixchamb.Audit.log_as(
      socket.assigns.current_admin,
      "delete_chamber",
      "chamber:#{chamber.slug}",
      %{
        id: chamber.id
      }
    )

    Chambers.delete(chamber)

    Phoenix.PubSub.broadcast(
      Mixchamb.PubSub,
      Chambers.topic(chamber.slug),
      {:chamber_closed, chamber.slug}
    )

    {:noreply,
     socket
     |> put_flash(:info, "Deleted chamber #{chamber.slug}.")
     |> push_navigate(to: ~p"/admin/chambers")}
  end

  def handle_event("kill_genserver", _params, socket) do
    slug = socket.assigns.slug

    case Registry.lookup(Mixchamb.Chambers.Registry, slug) do
      [{pid, _}] ->
        Mixchamb.Audit.log_as(socket.assigns.current_admin, "kill_chamber", "chamber:#{slug}", %{
          pid: inspect(pid)
        })

        Process.exit(pid, :kill)
        {:noreply, put_flash(socket, :info, "Killed GenServer — supervisor will restart it.")}

      _ ->
        {:noreply, put_flash(socket, :error, "No running GenServer for #{slug}.")}
    end
  end

  defp presence_topic(slug), do: "chamber:#{slug}:presence"

  ## Render helpers

  # One presentation for every status field in the overview grid:
  # a colored dot + a colored label. `tone` picks the colour pair;
  # `pulse?` (default false) animates the dot — used for the
  # "recording on" state since the live red-dot is the convention
  # users expect from any REC indicator.
  attr :tone, :atom, required: true, values: [:success, :warning, :muted, :danger]
  attr :label, :string, required: true
  attr :pulse?, :boolean, default: false

  defp status_pill(assigns) do
    ~H"""
    <span class={["inline-flex items-center gap-1.5", status_pill_text_class(@tone)]}>
      <span class={[
        "size-2 rounded-full",
        status_pill_dot_class(@tone),
        @pulse? && "animate-pulse"
      ]}>
      </span>
      {@label}
    </span>
    """
  end

  defp status_pill_text_class(:success), do: "text-emerald-600 dark:text-emerald-400"
  defp status_pill_text_class(:warning), do: "text-amber-600 dark:text-amber-400"
  defp status_pill_text_class(:muted), do: "text-muted-foreground"
  defp status_pill_text_class(:danger), do: "text-red-500"

  defp status_pill_dot_class(:success), do: "bg-emerald-500"
  defp status_pill_dot_class(:warning), do: "bg-amber-500"
  defp status_pill_dot_class(:muted), do: "bg-muted-foreground/50"
  defp status_pill_dot_class(:danger), do: "bg-red-500"

  defp format_uptime(nil), do: "—"

  defp format_uptime(ms) when is_integer(ms) do
    seconds = div(ms, 1000)

    cond do
      seconds < 60 -> "#{seconds}s"
      seconds < 3_600 -> "#{div(seconds, 60)}m #{rem(seconds, 60)}s"
      true -> "#{div(seconds, 3_600)}h #{rem(div(seconds, 60), 60)}m"
    end
  end

  defp note_label(%{payload: payload}) do
    instrument = payload["instrument"] || "?"
    note = payload["chord"] || payload["note"] || ""
    style = payload["style"] || ""
    "#{instrument}/#{style} · #{note}"
  end

  @impl true
  def render(assigns) do
    ~H"""
    <AdminLayouts.admin_shell
      current_view={MixchambWeb.Admin.ChambersLive}
      flash={@flash}
      banner={assigns[:banner]}
      draining?={assigns[:draining?] || false}
    >
      <%!-- Breadcrumb back to the list. --%>
      <.link
        navigate={~p"/admin/chambers"}
        class="inline-flex items-center gap-1 text-xs text-muted-foreground hover:text-foreground transition-colors"
      >
        <.icon name="hero-arrow-left-mini" class="size-3.5" /> Back to chambers
      </.link>

      <.header>
        <span class="font-mono">{@chamber.slug}</span>
        <:subtitle>
          {@chamber.title || "(no title)"}
        </:subtitle>
        <:actions>
          <.link
            navigate={~p"/chamber/#{@chamber.slug}"}
            class="inline-flex items-center gap-1.5 px-3 py-1.5 text-xs rounded-md border bg-card hover:bg-accent transition-colors"
            title="Open the user-facing chamber"
          >
            <.icon name="hero-arrow-top-right-on-square-mini" class="size-3.5" /> Open chamber
          </.link>
        </:actions>
      </.header>

      <%!-- Quick facts card. --%>
      <section class="rounded-xl border bg-card p-5">
        <dl class="grid grid-cols-2 md:grid-cols-4 gap-y-3 gap-x-4 text-sm">
          <div>
            <dt class="text-[11px] uppercase tracking-wider text-muted-foreground">Kind</dt>
            <dd class="font-mono">{@chamber.kind}</dd>
          </div>
          <div>
            <dt class="text-[11px] uppercase tracking-wider text-muted-foreground">State</dt>
            <dd>
              <%= cond do %>
                <% @chamber.creator_user_id == nil -> %>
                  <.status_pill tone={:warning} label="system" />
                <% @chamber.activated_at -> %>
                  <.status_pill tone={:success} label="active" />
                <% true -> %>
                  <.status_pill tone={:muted} label="grace" />
              <% end %>
            </dd>
          </div>
          <div>
            <dt class="text-[11px] uppercase tracking-wider text-muted-foreground">Recording</dt>
            <dd>
              <%= if @chamber.is_recording do %>
                <.status_pill tone={:danger} label="on" pulse?={true} />
              <% else %>
                <.status_pill tone={:muted} label="off" />
              <% end %>
            </dd>
          </div>
          <div>
            <dt class="text-[11px] uppercase tracking-wider text-muted-foreground">GenServer</dt>
            <dd>
              <%= if @server_info do %>
                <.status_pill tone={:success} label="running" />
              <% else %>
                <.status_pill tone={:muted} label="not started" />
              <% end %>
            </dd>
          </div>

          <div>
            <dt class="text-[11px] uppercase tracking-wider text-muted-foreground">Created</dt>
            <dd class="text-xs text-muted-foreground">{time_ago(@chamber.inserted_at)}</dd>
          </div>
          <div>
            <dt class="text-[11px] uppercase tracking-wider text-muted-foreground">Activated</dt>
            <dd class="text-xs text-muted-foreground">{time_ago(@chamber.activated_at)}</dd>
          </div>
          <div>
            <dt class="text-[11px] uppercase tracking-wider text-muted-foreground">Last activity</dt>
            <dd class="text-xs text-muted-foreground">{time_ago(@chamber.last_activity_at)}</dd>
          </div>
          <div>
            <dt class="text-[11px] uppercase tracking-wider text-muted-foreground">Uptime</dt>
            <dd class="text-xs text-muted-foreground tabular-nums">
              {format_uptime(@server_info && @server_info.uptime_ms)}
            </dd>
          </div>
        </dl>
      </section>

      <%!-- Stat tiles. --%>
      <h2 class="mt-6 mb-2 text-xs uppercase tracking-wider text-muted-foreground font-display">
        Live
      </h2>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">Jamming</div>
          <div class="mt-1 text-2xl font-bold tabular-nums">{map_size(@presences)}</div>
        </div>
        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">
            Buffered events
          </div>
          <div class="mt-1 text-2xl font-bold tabular-nums">
            {(@server_info && @server_info.event_count) || 0}
          </div>
          <div class="text-[10px] text-muted-foreground mt-1">
            in-memory ring, last 200 max
          </div>
        </div>
        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">
            Recorded events
          </div>
          <div class="mt-1 text-2xl font-bold tabular-nums">{@recorded_count}</div>
          <div class="text-[10px] text-muted-foreground mt-1">
            persisted to chamber_events
          </div>
        </div>
        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">Restarts</div>
          <div class="mt-1 text-2xl font-bold tabular-nums">{@restart_count}</div>
          <div class="text-[10px] text-muted-foreground mt-1">since BEAM start</div>
        </div>
      </div>

      <%!-- Presence list + recent notes side by side on wide. --%>
      <div class="mt-6 grid grid-cols-1 lg:grid-cols-2 gap-4">
        <section class="rounded-xl border bg-card overflow-hidden">
          <header class="px-4 py-2 border-b bg-muted/30">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Who's here
            </h3>
          </header>
          <ul
            :if={map_size(@presences) > 0}
            class="divide-y max-h-80 overflow-y-auto"
          >
            <li
              :for={{user_id, %{metas: [meta | _]}} <- @presences}
              class="px-4 py-2 text-sm flex items-center justify-between gap-3"
            >
              <div class="min-w-0">
                <div class="truncate">
                  {meta[:alias] || meta.display_name}
                </div>
                <div class="text-[11px] text-muted-foreground font-mono truncate">
                  <%!-- Trailing space inside the interpolation so the
                       HEEx formatter has nothing to "pad" between the
                       two expressions — keeps mix format stable
                       across Elixir patch versions. --%>
                  <span :if={meta[:alias]}>{meta.display_name <> " · "}</span>
                  {meta.instrument} · {user_id}
                </div>
              </div>
              <span
                :if={meta[:node]}
                title={"Connected via #{meta.node}"}
                class="shrink-0 inline-flex items-center px-2 py-0.5 rounded-md border bg-muted/50 text-[10px] font-mono text-muted-foreground"
              >
                {meta.node}
              </span>
            </li>
          </ul>
          <div
            :if={map_size(@presences) == 0}
            class="px-4 py-8 text-center text-sm text-muted-foreground"
          >
            Nobody jamming right now.
          </div>
        </section>

        <section class="rounded-xl border bg-card overflow-hidden">
          <header class="px-4 py-2 border-b bg-muted/30 flex items-center justify-between">
            <h3 class="text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Recent notes
            </h3>
            <span class="text-[10px] text-muted-foreground">last 20</span>
          </header>
          <ul
            :if={@recent_notes != []}
            class="divide-y max-h-80 overflow-y-auto"
          >
            <li
              :for={ev <- @recent_notes}
              class="px-4 py-1.5 text-xs font-mono flex items-center justify-between gap-3"
            >
              <span class="text-muted-foreground truncate">
                {ev.payload["display_name"] || ev.payload["user_id"]}
              </span>
              <span class="truncate">{note_label(ev)}</span>
            </li>
          </ul>
          <div
            :if={@recent_notes == []}
            class="px-4 py-8 text-center text-sm text-muted-foreground"
          >
            Waiting for notes…
          </div>
        </section>
      </div>

      <%!-- Danger zone. --%>
      <section class="mt-6 rounded-xl border border-destructive/30 bg-destructive/5 p-5">
        <h3 class="text-sm font-semibold font-display tracking-tight text-destructive">
          Danger zone
        </h3>
        <p class="text-xs text-muted-foreground mt-1 mb-4">
          Both actions are logged to the audit trail.
        </p>
        <div class="flex flex-wrap items-center gap-2">
          <.button
            :if={@server_info}
            variant="outline"
            phx-click="kill_genserver"
            data-confirm={"Kill the GenServer for #{@chamber.slug}? The supervisor will restart it within ~100 ms."}
          >
            Kill GenServer
          </.button>
          <.button
            variant="outline"
            phx-click="delete_chamber"
            data-confirm={"Force-delete chamber #{@chamber.slug}? Connected users get kicked. This can't be undone."}
            class="text-destructive hover:bg-destructive/10 hover:text-destructive"
          >
            Delete chamber
          </.button>
        </div>
      </section>
    </AdminLayouts.admin_shell>
    """
  end
end
