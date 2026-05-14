defmodule Mixwave.Drain do
  @moduledoc """
  Graceful-shutdown coordinator. Sits at the tail of
  `Mixwave.Application`'s child list so it's the *first* process
  terminated when SIGTERM arrives (children stop in reverse start
  order). Its `terminate/2` callback:

    1. PubSub-broadcasts `{:node_draining, Node.self()}` on
       `topic/0`. Every browser LV is subscribed via
       `MixwaveWeb.Live.BannerHook` and pushes a "Server restarting"
       strip when the message lands.
    2. Sleeps `@drain_grace_ms` so the broadcast actually reaches
       the WebSockets before the Endpoint starts tearing them
       down.

  PubSub + Endpoint are still alive during this window because
  they appear earlier in the child list and therefore get
  terminated *after* Drain.

  This is a Fly / k8s rolling-deploy concern; in dev with code
  reloading SIGTERM doesn't normally happen, so `Process.sleep` here
  shouldn't affect the dev cycle.
  """
  use GenServer

  # 3 s gives ChamberServer.terminate room to flush its recording
  # queue and lets LVs paint the warning before WebSockets close.
  # The default Fly SIGTERM-to-SIGKILL grace is 5 s, so 3 s leaves
  # 2 s of slack for the rest of the supervision tree.
  @drain_grace_ms 3_000

  @topic "system:drain"

  @doc "PubSub topic browser LVs subscribe to."
  def topic, do: @topic

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(_) do
    # Without trap_exit, the supervisor's shutdown signal kills us
    # immediately; terminate/2 never runs.
    Process.flag(:trap_exit, true)
    {:ok, %{}}
  end

  @impl true
  def terminate(_reason, _state) do
    # local_broadcast — only LVs hosted on this node need to know.
    # Across the cluster other nodes don't care that we're going
    # away; their Presence + PubSub will converge naturally.
    Phoenix.PubSub.local_broadcast(
      Mixwave.PubSub,
      @topic,
      {:node_draining, Node.self()}
    )

    Process.sleep(@drain_grace_ms)
    :ok
  end
end
