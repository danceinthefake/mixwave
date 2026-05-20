defmodule MixwaveWeb.Admin.ClusterLive do
  @moduledoc """
  Admin → Cluster tab. Shows the BEAM nodes this app is currently
  clustered with, plus per-node telemetry (uptime, processes,
  memory) gathered via `:rpc.call/4`.

  Two operations beyond observation:

    * **Connect**: explicitly attach to a remote node by name.
      Useful in dev when running two `iex --sname` instances
      against the same DB and you want to wire them up by hand.
      In prod the `dns_cluster` library does this automatically.
    * **Drain**: kill the target node's `MixwaveWeb.Endpoint`. The
      node's own supervisor restarts it within ~100 ms; in the
      meantime every WebSocket on that node drops and reconnects,
      and behind a load balancer those clients land on a sibling
      node. On a single laptop that just demonstrates the kill +
      restart path — there's no LB to round-robin to.

  Cluster topology is push-driven: the LV monitors `:nodeup` /
  `:nodedown` via `:net_kernel.monitor_nodes/1` so changes appear
  the instant they happen, not on the next poll.
  """
  use MixwaveWeb, :live_view
  require Logger

  alias MixwaveWeb.Admin.Layouts, as: AdminLayouts

  # Tick is purely for live memory + process-count refresh; the
  # node list itself updates immediately via :nodeup / :nodedown.
  @poll_ms 2_000

  @impl true
  def mount(_params, _session, socket) do
    if connected?(socket) do
      :net_kernel.monitor_nodes(true)
      :timer.send_interval(@poll_ms, :tick)
    end

    {:ok,
     socket
     |> assign(:connect_input, "")
     |> assign(:connect_error, nil)
     |> load()}
  end

  @impl true
  def handle_info(:tick, socket), do: {:noreply, load(socket)}

  def handle_info({:nodeup, node}, socket) do
    Logger.info("[admin/cluster] nodeup: #{node}")
    {:noreply, load(socket)}
  end

  def handle_info({:nodedown, node}, socket) do
    Logger.info("[admin/cluster] nodedown: #{node}")
    {:noreply, load(socket)}
  end

  @impl true
  def handle_event("update_input", %{"value" => value}, socket) do
    {:noreply, assign(socket, :connect_input, value)}
  end

  def handle_event("connect", %{"node" => raw}, socket) do
    target = String.trim(raw)

    cond do
      target == "" ->
        {:noreply, assign(socket, :connect_error, "Node name can't be empty.")}

      not String.contains?(target, "@") ->
        {:noreply,
         assign(
           socket,
           :connect_error,
           "Node name needs an @ — e.g. 'mixwave2@hostname'."
         )}

      true ->
        node = String.to_atom(target)
        Logger.info("[admin/cluster] connect attempt: #{inspect(node)}")

        case Node.connect(node) do
          true ->
            Mixwave.Audit.log_as(
              socket.assigns.current_admin,
              "connect_node",
              "node:#{node}",
              %{}
            )

            {:noreply,
             socket
             |> put_flash(:info, "Connected to #{node}.")
             |> assign(:connect_input, "")
             |> assign(:connect_error, nil)
             |> load()}

          false ->
            {:noreply, assign(socket, :connect_error, "Couldn't reach #{node}.")}

          :ignored ->
            {:noreply,
             assign(
               socket,
               :connect_error,
               "Local node isn't distributed (start with --sname or --name)."
             )}
        end
    end
  end

  def handle_event("disconnect", %{"node" => target}, socket) do
    node = String.to_atom(target)
    Logger.warning("[admin/cluster] disconnect: #{inspect(node)}")
    Mixwave.Audit.log_as(socket.assigns.current_admin, "disconnect_node", "node:#{node}", %{})
    Node.disconnect(node)
    {:noreply, load(socket)}
  end

  def handle_event("drain", %{"node" => target}, socket) do
    node = String.to_atom(target)
    Logger.warning("[admin/cluster] drain: #{inspect(node)}")
    Mixwave.Audit.log_as(socket.assigns.current_admin, "drain_node", "node:#{node}", %{})

    result =
      cond do
        node == Node.self() ->
          drain_local()

        true ->
          # :rpc returns {:badrpc, reason} on failure, otherwise
          # whatever the called function returns.
          :rpc.call(node, __MODULE__, :drain_local, [], 5_000)
      end

    msg =
      case result do
        :ok ->
          "Drained #{node} — endpoint cycled; clients will reconnect."

        {:error, reason} ->
          "Drain failed on #{node}: #{inspect(reason)}"

        {:badrpc, reason} ->
          "RPC failed reaching #{node}: #{inspect(reason)}"

        other ->
          "Drain returned: #{inspect(other)}"
      end

    {:noreply, socket |> put_flash(:info, msg) |> load()}
  end

  @doc """
  Cleanly cycles the local node's `MixwaveWeb.Endpoint`: ask the
  app supervisor to terminate it (releases the OS port), then ask
  it to restart it. Public so peers can invoke this via
  `:rpc.call/4` from the Drain button on a remote-node row.

  Earlier this was `Process.exit(pid, :kill)`. That looked dramatic
  but the brutal kill leaves port 4000/4001 in TIME_WAIT for a
  beat; the supervisor's automatic restart attempts to re-bind
  immediately, fails with EADDRINUSE, retries, and after three
  failures inside five seconds the whole app supervisor gives up
  and the node goes dark. The supervisor-controlled cycle below
  gives the listener a chance to drop the port before the new
  Endpoint takes it.
  """
  def drain_local do
    case Supervisor.terminate_child(Mixwave.Supervisor, MixwaveWeb.Endpoint) do
      :ok ->
        case Supervisor.restart_child(Mixwave.Supervisor, MixwaveWeb.Endpoint) do
          {:ok, _pid} -> :ok
          {:ok, _pid, _info} -> :ok
          {:error, reason} -> {:error, {:restart_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:terminate_failed, reason}}
    end
  end

  ## Internal

  defp load(socket) do
    self_node = Node.self()
    nodes = [self_node | Node.list()]

    rows =
      Enum.map(nodes, fn node ->
        {info, rtt_us} =
          if node == self_node do
            {local_info(), nil}
          else
            info =
              case :rpc.call(node, __MODULE__, :local_info, [], 1_500) do
                {:badrpc, _} = err -> %{error: err}
                ok -> ok
              end

            {info, measure_rtt(node)}
          end

        Map.merge(info, %{node: node, self?: node == self_node, rtt_us: rtt_us})
      end)

    assign(socket, :nodes, rows)
  end

  # Round-trip ping for an RTT readout. Calls `:erlang.node/0` on
  # the peer — it returns the peer's own node atom and does no real
  # work, so the timing is dominated by network + serialization, not
  # the remote computation. Returns microseconds (nil on failure).
  defp measure_rtt(node) do
    t0 = :erlang.monotonic_time(:microsecond)

    try do
      _ = :erpc.call(node, :erlang, :node, [], 1_500)
      :erlang.monotonic_time(:microsecond) - t0
    catch
      _kind, _reason -> nil
    end
  end

  @doc """
  Snapshot of this node's BEAM telemetry. Public so the LV can
  fetch it via `:rpc` from peers.
  """
  def local_info do
    {uptime_ms, _} = :erlang.statistics(:wall_clock)

    %{
      uptime_ms: uptime_ms,
      processes: :erlang.system_info(:process_count),
      memory_total: :erlang.memory(:total),
      schedulers: :erlang.system_info(:schedulers_online),
      otp_release: List.to_string(:erlang.system_info(:otp_release))
    }
  end

  ## Helpers

  defp format_memory(nil), do: "—"
  defp format_memory(bytes) when bytes < 1_024, do: "#{bytes} B"
  defp format_memory(bytes) when bytes < 1_024 * 1_024, do: "#{div(bytes, 1_024)} KB"
  defp format_memory(bytes), do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_uptime(ms) when not is_integer(ms), do: "—"
  defp format_uptime(ms) when ms < 60_000, do: "#{div(ms, 1_000)}s"
  defp format_uptime(ms) when ms < 3_600_000, do: "#{div(ms, 60_000)}m"
  defp format_uptime(ms) when ms < 86_400_000, do: "#{div(ms, 3_600_000)}h"
  defp format_uptime(ms), do: "#{div(ms, 86_400_000)}d"

  defp format_rtt(nil), do: "—"
  defp format_rtt(us) when us < 10_000, do: "#{Float.round(us / 1_000, 1)} ms"
  defp format_rtt(us), do: "#{round(us / 1_000)} ms"

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
        Cluster
        <:subtitle>
          BEAM nodes this app is currently connected to. Connect
          attaches a remote node manually; Drain kills its endpoint
          (the supervisor restarts within ~100 ms).
        </:subtitle>
      </.header>

      <%!-- Connect form. In dev — when nodes are started with
            `iex --sname` — Node.connect/1 wires them up if the
            name resolves and the cookies match. --%>
      <form
        phx-submit="connect"
        class="rounded-xl border bg-card p-4 mb-6 flex flex-wrap items-end gap-3"
      >
        <div class="flex-1 min-w-[16rem] space-y-1">
          <label class="text-xs uppercase tracking-wider text-muted-foreground">
            Connect node
          </label>
          <input
            type="text"
            name="node"
            value={@connect_input}
            phx-keyup="update_input"
            phx-debounce="200"
            placeholder="e.g. mixwave2@your-hostname"
            class="w-full rounded-md border bg-background px-3 py-2 text-sm font-mono focus:outline-none focus:ring-2 focus:ring-ring"
          />
        </div>
        <.button type="submit" variant="outline">Connect</.button>
        <p :if={@connect_error} class="basis-full text-xs text-destructive mt-1">
          {@connect_error}
        </p>
      </form>

      <div class="rounded-lg border bg-card overflow-hidden">
        <table class="w-full text-sm">
          <thead class="bg-muted/40 text-xs uppercase tracking-wider text-muted-foreground">
            <tr class="text-left">
              <th class="px-4 py-2">Node</th>
              <th class="px-4 py-2 text-right">RTT</th>
              <th class="px-4 py-2 text-right">Uptime</th>
              <th class="px-4 py-2 text-right">Processes</th>
              <th class="px-4 py-2 text-right">Memory</th>
              <th class="px-4 py-2 text-right">Schedulers</th>
              <th class="px-4 py-2 text-right">OTP</th>
              <th class="px-4 py-2"></th>
            </tr>
          </thead>
          <tbody class="divide-y">
            <tr :for={n <- @nodes} class="align-top">
              <td class="px-4 py-3">
                <div class="font-mono text-xs font-medium">{n.node}</div>
                <div class="text-[11px] text-muted-foreground">
                  <span :if={n.self?} class="text-emerald-600 dark:text-emerald-400">
                    self
                  </span>
                  <span :if={not n.self? and Map.has_key?(n, :error)} class="text-destructive">
                    rpc failed
                  </span>
                  <span :if={not n.self? and not Map.has_key?(n, :error)}>
                    connected
                  </span>
                </div>
              </td>
              <td class="px-4 py-3 text-right tabular-nums text-muted-foreground">
                {format_rtt(n[:rtt_us])}
              </td>
              <td class="px-4 py-3 text-right tabular-nums text-muted-foreground">
                {format_uptime(n[:uptime_ms])}
              </td>
              <td class="px-4 py-3 text-right tabular-nums">
                {n[:processes] || "—"}
              </td>
              <td class="px-4 py-3 text-right tabular-nums text-muted-foreground">
                {format_memory(n[:memory_total])}
              </td>
              <td class="px-4 py-3 text-right tabular-nums text-muted-foreground">
                {n[:schedulers] || "—"}
              </td>
              <td class="px-4 py-3 text-right text-muted-foreground">
                {n[:otp_release] || "—"}
              </td>
              <td class="px-4 py-3 text-right space-x-1">
                <.button
                  :if={not n.self?}
                  variant="outline"
                  phx-click="disconnect"
                  phx-value-node={Atom.to_string(n.node)}
                  data-confirm={"Disconnect from #{n.node}? PubSub fan-out across to that node will stop."}
                >
                  Disconnect
                </.button>
                <.button
                  variant="outline"
                  phx-click="drain"
                  phx-value-node={Atom.to_string(n.node)}
                  data-confirm={"Drain #{n.node}? Its endpoint dies and clients reconnect."}
                  class="text-destructive hover:bg-destructive/10 hover:text-destructive"
                >
                  Drain
                </.button>
              </td>
            </tr>
          </tbody>
        </table>
      </div>

      <div class="mt-8 rounded-xl border bg-card/50 p-4 space-y-2 text-xs text-muted-foreground">
        <div class="font-medium text-foreground font-display">Run two local nodes</div>
        <p>
          The app's distribution stack is wired up but a single
          <code class="px-1 rounded bg-muted">mix phx.server</code>
          launches a non-distributed BEAM. To exercise this page,
          start two named nodes against the same DB:
        </p>
        <pre class="whitespace-pre font-mono text-[11px] bg-muted/40 rounded p-3 mt-1 overflow-x-auto"><%= "Terminal 1: PORT=4000 iex --sname mixwave1 --cookie shared -S mix phx.server\nTerminal 2: PORT=4001 SKIP_VITE=1 iex --sname mixwave2 --cookie shared -S mix phx.server" %></pre>
        <p class="text-[11px]">
          The second node sets <code class="px-1 rounded bg-muted">SKIP_VITE=1</code>
          because Vite only fits on port 5173 once; the second
          BEAM still gets HMR from the first node's Vite.
        </p>
        <p>
          Then visit /admin/cluster on either, type the peer node
          name in <strong>Connect</strong>, and watch this table
          grow. <strong>Drain</strong>
          on the remote row kills its <code class="px-1 rounded bg-muted">MixwaveWeb.Endpoint</code>
          via :rpc;
          the supervisor brings it back within milliseconds.
        </p>
      </div>
    </AdminLayouts.admin_shell>
    """
  end
end
