defmodule MixwaveWeb.Live.BannerHook do
  @moduledoc """
  on_mount hook that wires every browser LV to two
  layout-level signals:

    * **Admin banner** — `Mixwave.Banners.topic/0`. Reads the
      currently-active banner from the DB once on mount and
      subscribes for future `{:banner_changed, banner}` pushes.
    * **Node drain** — `Mixwave.Drain.topic/0`. When the host
      node is about to shut down it broadcasts `{:node_draining,
      Node.self()}`; we flip a `:draining?` assign so the layout
      can render a "server restarting" strip while WebSockets
      are still alive.

  Both signals piggy-back on a single `attach_hook(:handle_info)`
  so individual LVs don't need to write their own clauses.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, connected?: 1]

  alias Mixwave.{Banners, Drain}

  def on_mount(:default, _params, _session, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Mixwave.PubSub, Banners.topic())
      Phoenix.PubSub.subscribe(Mixwave.PubSub, Drain.topic())
    end

    socket =
      socket
      |> assign(:banner, Banners.current_banner())
      |> assign(:draining?, false)
      |> attach_hook(:banner_listener, :handle_info, &handle_info/2)

    {:cont, socket}
  end

  # Plant handle_info clauses on every LV under this on_mount so
  # the layout-level signals work without per-LV wiring. Each
  # clause returns :cont so the LV's own handle_info clauses still
  # run for unrelated messages.
  defp handle_info({:banner_changed, banner}, socket) do
    {:cont, assign(socket, :banner, banner)}
  end

  defp handle_info({:node_draining, _node}, socket) do
    {:cont, assign(socket, :draining?, true)}
  end

  defp handle_info(_other, socket), do: {:cont, socket}
end
