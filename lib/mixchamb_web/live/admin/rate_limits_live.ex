defmodule MixchambWeb.Admin.RateLimitsLive do
  @moduledoc """
  Admin → Rate limits tab. Two views into the `note` rate-limiter:

    * **Currently saturated** — buckets from
      `Mixchamb.RateLimiter`'s ETS table whose count is at or near
      the cap right now (≥ 80%). Useful for catching someone
      hammering live.
    * **Lifetime drops** — counters maintained by
      `Mixchamb.Telemetry.RateLimitDrops` since the BEAM started,
      grouped by `{user_id, slug}`. Useful for "who has been
      consistently bouncing off the cap."

  Resolves user_id to a display_name via the Accounts context so
  the table reads as names, not UUIDs. Deleted-since users fall
  back to a "(deleted user)" label.
  """
  use MixchambWeb, :live_view

  alias Mixchamb.{Accounts, RateLimiter}
  alias Mixchamb.Telemetry.RateLimitDrops
  alias MixchambWeb.Admin.Layouts, as: AdminLayouts
  import MixchambWeb.Admin.Format, only: [time_ago_ms: 1]

  # Mirrors ChamberLive's @note_rate_max + @note_rate_window_ms.
  # Worth keeping in sync if those change.
  @note_rate_max 20
  @note_rate_window_ms 1_000
  @saturation_threshold_pct 80

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2_000, :tick)

    {:ok, assign(socket, build_assigns())}
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, assign(socket, build_assigns())}

  @impl true
  def handle_event("reset_bucket", %{"user_id" => user_id, "slug" => slug}, socket)
      when is_binary(user_id) and is_binary(slug) do
    # Mirror the key shape ChamberLive's `note` handler uses.
    # Idempotent: a stale row that's already aged out of ETS is a
    # no-op delete.
    RateLimiter.reset_key({:note, user_id, slug})

    Mixchamb.Audit.log_as(
      socket.assigns.current_admin,
      "reset_rate_limit_bucket",
      "user:#{user_id}",
      %{slug: slug}
    )

    {:noreply,
     socket
     |> put_flash(:info, "Reset rate-limit bucket for user in #{slug}.")
     |> assign(build_assigns())}
  end

  defp build_assigns do
    drops = RateLimitDrops.snapshot()
    saturated = collect_saturated()

    %{
      total_drops: drops.total,
      drop_rows: drops.rows |> Enum.take(100) |> resolve_users(),
      saturated: resolve_users(saturated),
      note_rate_max: @note_rate_max,
      note_rate_window_ms: @note_rate_window_ms,
      saturation_threshold_pct: @saturation_threshold_pct
    }
  end

  # Walk the ETS table for buckets still in the current 1 s
  # window whose count is at or above the saturation threshold.
  defp collect_saturated do
    now = System.monotonic_time(:millisecond)
    threshold = div(@note_rate_max * @saturation_threshold_pct, 100)

    :ets.foldl(
      fn
        {{:note, user_id, slug}, window_start, count}, acc
        when count >= threshold and now - window_start < @note_rate_window_ms ->
          [
            %{user_id: user_id, slug: slug, count: count, window_start: window_start}
            | acc
          ]

        _other, acc ->
          acc
      end,
      [],
      RateLimiter.table()
    )
    |> Enum.sort_by(& &1.count, :desc)
  end

  # Bulk-resolve user_ids → display names + aliases without one
  # query per row. Anything missing renders as "(deleted)" so the
  # row still tells the admin which slug was hit.
  defp resolve_users(rows) when is_list(rows) do
    user_ids = rows |> Enum.map(& &1.user_id) |> Enum.uniq()
    users = Accounts.list_users_by_ids(user_ids)

    Enum.map(rows, fn row ->
      case Map.get(users, row.user_id) do
        nil -> Map.merge(row, %{display_name: nil, alias: nil})
        u -> Map.merge(row, %{display_name: u.display_name, alias: u.alias})
      end
    end)
  end

  ## Render helpers

  defp user_label(%{alias: a, display_name: name}) when is_binary(a) and a != "" do
    "#{a} (#{name})"
  end

  defp user_label(%{display_name: name}) when is_binary(name), do: name
  defp user_label(%{user_id: id}), do: "(deleted) · #{id}"

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
        Rate limits
        <:subtitle>
          Every <code class="font-mono">note</code>
          event hits a {@note_rate_max}/sec budget per (user × chamber). Drops past the cap are silent client-side; here's where they show up.
        </:subtitle>
      </.header>

      <%!-- Currently saturated. --%>
      <h2 class="mt-4 mb-2 text-xs uppercase tracking-wider text-muted-foreground font-display">
        Saturated right now
      </h2>
      <p class="text-xs text-muted-foreground mb-3">
        Buckets in the current {@note_rate_window_ms}-ms window whose count is at or above {@saturation_threshold_pct}% of the cap.
      </p>

      <div
        :if={@saturated == []}
        class="rounded-lg border border-dashed bg-card/50 p-6 text-center text-sm text-muted-foreground"
      >
        Nobody pushing near the cap right now.
      </div>

      <div :if={@saturated != []} class="rounded-xl border bg-card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-[11px] uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2">User</th>
              <th class="px-4 py-2">Chamber</th>
              <th class="px-4 py-2 text-right">Count</th>
              <th class="px-4 py-2 text-right">Bucket</th>
              <th class="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={row <- @saturated}>
              <td class="px-4 py-2">{user_label(row)}</td>
              <td class="px-4 py-2 font-mono text-xs">
                <.link navigate={~p"/admin/chambers/#{row.slug}"} class="hover:underline">
                  {row.slug}
                </.link>
              </td>
              <td class="px-4 py-2 text-right tabular-nums">
                <span class={[
                  row.count >= @note_rate_max && "text-destructive font-semibold",
                  row.count < @note_rate_max && "text-amber-600 dark:text-amber-400"
                ]}>
                  {row.count}/{@note_rate_max}
                </span>
              </td>
              <td class="px-4 py-2 text-right text-xs text-muted-foreground tabular-nums">
                opened {time_ago_ms(row.window_start)}
              </td>
              <td class="px-4 py-2 text-right">
                <%!-- Per-row reset. Mostly useful when a client
                     ran out of control and you want to unblock
                     them without restarting the BEAM. The audit
                     event records the slug + user_id for
                     after-the-fact review. --%>
                <.button
                  variant="outline"
                  phx-click="reset_bucket"
                  phx-value-user_id={row.user_id}
                  phx-value-slug={row.slug}
                  data-confirm={"Reset this user's rate-limit bucket for #{row.slug}? They'll be able to send notes again immediately."}
                  class="text-xs"
                >
                  Reset
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Lifetime drops. --%>
      <h2 class="mt-8 mb-2 text-xs uppercase tracking-wider text-muted-foreground font-display">
        Lifetime drops
      </h2>
      <p class="text-xs text-muted-foreground mb-3">
        Total dropped events per (user × chamber) since the BEAM started.
        <span class="text-foreground font-medium tabular-nums">{@total_drops}</span>
        across all users.
      </p>

      <div
        :if={@drop_rows == []}
        class="rounded-lg border border-dashed bg-card/50 p-6 text-center text-sm text-muted-foreground"
      >
        No drops recorded since BEAM start.
      </div>

      <div :if={@drop_rows != []} class="rounded-xl border bg-card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-[11px] uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2">User</th>
              <th class="px-4 py-2">Chamber</th>
              <th class="px-4 py-2 text-right">Drops</th>
              <th class="px-4 py-2 text-right">Last drop</th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={row <- @drop_rows}>
              <td class="px-4 py-2">{user_label(row)}</td>
              <td class="px-4 py-2 font-mono text-xs">
                <.link navigate={~p"/admin/chambers/#{row.slug}"} class="hover:underline">
                  {row.slug}
                </.link>
              </td>
              <td class="px-4 py-2 text-right tabular-nums">{row.count}</td>
              <td class="px-4 py-2 text-right text-xs text-muted-foreground tabular-nums">
                {time_ago_ms(row.last_drop_at)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>
    </AdminLayouts.admin_shell>
    """
  end
end
