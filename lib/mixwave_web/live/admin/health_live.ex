defmodule MixwaveWeb.Admin.HealthLive do
  @moduledoc """
  Admin → Health tab. BEAM + Postgres + ETS surface-area metrics
  ticked every 2 s — the things an oncall would glance at first
  ("are we OK right now").

  Stays focused: no graphs, no time series. For deeper digging
  the LiveDashboard at `/dev/dashboard` covers per-process state,
  process trees, scheduler heat-maps, etc.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.SystemHealth
  alias MixwaveWeb.Admin.Layouts, as: AdminLayouts

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket), do: :timer.send_interval(2_000, :tick)
    {:ok, assign(socket, :snap, SystemHealth.snapshot())}
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, assign(socket, :snap, SystemHealth.snapshot())}

  ## Render helpers

  defp format_bytes(n) when is_integer(n) and n < 1024, do: "#{n} B"

  defp format_bytes(n) when is_integer(n) and n < 1024 * 1024,
    do: "#{Float.round(n / 1024, 1)} KB"

  defp format_bytes(n) when is_integer(n) and n < 1024 * 1024 * 1024,
    do: "#{Float.round(n / 1024 / 1024, 1)} MB"

  defp format_bytes(n) when is_integer(n), do: "#{Float.round(n / 1024 / 1024 / 1024, 2)} GB"
  defp format_bytes(_), do: "—"

  defp format_count(n) when is_integer(n) and n >= 1_000_000_000,
    do: "#{Float.round(n / 1_000_000_000, 2)}B"

  defp format_count(n) when is_integer(n) and n >= 1_000_000,
    do: "#{Float.round(n / 1_000_000, 1)}M"

  defp format_count(n) when is_integer(n) and n >= 1_000,
    do: "#{Float.round(n / 1_000, 1)}K"

  defp format_count(n) when is_integer(n), do: "#{n}"

  defp pct(used, total) when is_integer(used) and is_integer(total) and total > 0,
    do: round(used * 100 / total)

  defp pct(_, _), do: 0

  defp pct_class(p) when p >= 90, do: "text-destructive"
  defp pct_class(p) when p >= 75, do: "text-amber-600 dark:text-amber-400"
  defp pct_class(_), do: "text-muted-foreground"

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
        Health
        <:subtitle>
          BEAM, Postgres, and ETS surface-area snapshot — what an
          oncall would glance at first. Refreshes every 2 s.
        </:subtitle>
      </.header>

      <%!-- Top stat grid: the things you'd page someone over. --%>
      <h2 class="mt-2 mb-2 text-xs uppercase tracking-wider text-muted-foreground font-display">
        Now
      </h2>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">Processes</div>
          <div class="mt-1 text-2xl font-bold tabular-nums">
            {format_count(@snap.beam.process_count)}
          </div>
          <div class={[
            "text-[10px] mt-1 tabular-nums",
            pct_class(pct(@snap.beam.process_count, @snap.beam.process_limit))
          ]}>
            {pct(@snap.beam.process_count, @snap.beam.process_limit)}% of {format_count(
              @snap.beam.process_limit
            )}
          </div>
        </div>

        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">
            Memory total
          </div>
          <div class="mt-1 text-2xl font-bold tabular-nums">
            {format_bytes(@snap.memory.total)}
          </div>
          <div class="text-[10px] text-muted-foreground mt-1">
            processes {format_bytes(@snap.memory.processes)}
          </div>
        </div>

        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">Atoms</div>
          <div class="mt-1 text-2xl font-bold tabular-nums">
            {format_count(@snap.beam.atom_count)}
          </div>
          <div class={[
            "text-[10px] mt-1 tabular-nums",
            pct_class(pct(@snap.beam.atom_count, @snap.beam.atom_limit))
          ]}>
            {pct(@snap.beam.atom_count, @snap.beam.atom_limit)}% of {format_count(
              @snap.beam.atom_limit
            )}
          </div>
        </div>

        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">Run queue</div>
          <div class="mt-1 text-2xl font-bold tabular-nums">{@snap.beam.run_queue}</div>
          <div class="text-[10px] text-muted-foreground mt-1">
            {@snap.beam.schedulers_online}/{@snap.beam.schedulers_total} schedulers online
          </div>
        </div>

        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">
            DB connections
          </div>
          <div class="mt-1 text-2xl font-bold tabular-nums">
            <span :if={@snap.db.status == :ok}>{@snap.db.active_connections}</span>
            <span
              :if={@snap.db.status == :unreachable}
              class="text-destructive text-base"
            >
              unreachable
            </span>
          </div>
          <div class="text-[10px] text-muted-foreground mt-1">
            pool size {@snap.db.pool_size}
          </div>
        </div>

        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">
            Chamber servers
          </div>
          <div class="mt-1 text-2xl font-bold tabular-nums">{@snap.chambers.running}</div>
          <div class="text-[10px] text-muted-foreground mt-1">live GenServers</div>
        </div>

        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">Reductions</div>
          <div class="mt-1 text-2xl font-bold tabular-nums">
            {format_count(@snap.beam.reductions_total)}
          </div>
          <div class="text-[10px] text-muted-foreground mt-1">
            cumulative since BEAM start
          </div>
        </div>

        <div class="rounded-lg border bg-card p-4">
          <div class="text-[11px] uppercase tracking-wider text-muted-foreground">Ports</div>
          <div class="mt-1 text-2xl font-bold tabular-nums">{@snap.beam.port_count}</div>
          <div class="text-[10px] text-muted-foreground mt-1">
            file descriptors + sockets
          </div>
        </div>
      </div>

      <%!-- Memory breakdown. --%>
      <h2 class="mt-8 mb-2 text-xs uppercase tracking-wider text-muted-foreground font-display">
        Memory breakdown
      </h2>
      <div class="rounded-xl border bg-card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-[11px] uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2">Segment</th>
              <th class="px-4 py-2 text-right">Bytes</th>
              <th class="px-4 py-2 text-right">% of total</th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={
              {label, value} <- [
                {"Processes", @snap.memory.processes},
                {"Binary", @snap.memory.binary},
                {"Code", @snap.memory.code},
                {"ETS", @snap.memory.ets},
                {"Atom", @snap.memory.atom},
                {"System", @snap.memory.system}
              ]
            }>
              <td class="px-4 py-2">{label}</td>
              <td class="px-4 py-2 text-right tabular-nums">{format_bytes(value)}</td>
              <td class="px-4 py-2 text-right tabular-nums text-muted-foreground">
                {pct(value, @snap.memory.total)}%
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- Our ETS tables. --%>
      <h2 class="mt-8 mb-2 text-xs uppercase tracking-wider text-muted-foreground font-display">
        Our ETS tables
      </h2>
      <p class="text-xs text-muted-foreground mb-3">
        Tables mixwave creates directly. Phoenix-internal tables
        (Presence, PubSub) are visible under <code class="font-mono">/dev/dashboard</code>.
      </p>
      <div class="rounded-xl border bg-card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-[11px] uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2">Table</th>
              <th class="px-4 py-2 text-right">Rows</th>
              <th class="px-4 py-2 text-right">Memory</th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={row <- @snap.ets}>
              <td class="px-4 py-2">
                <div>{row.label}</div>
                <div class="text-[10px] text-muted-foreground font-mono">
                  {inspect(row.table)}
                </div>
              </td>
              <td class="px-4 py-2 text-right tabular-nums">
                <span :if={row.exists?}>{format_count(row.size)}</span>
                <span
                  :if={not row.exists?}
                  class="text-destructive"
                >
                  not started
                </span>
              </td>
              <td class="px-4 py-2 text-right tabular-nums text-muted-foreground">
                {format_bytes(row.memory_bytes)}
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <%!-- BEAM identity footer. --%>
      <div class="mt-8 text-[11px] text-muted-foreground tabular-nums font-mono">
        OTP {@snap.beam.otp_release} · {@snap.beam.system_version}
      </div>
    </AdminLayouts.admin_shell>
    """
  end
end
