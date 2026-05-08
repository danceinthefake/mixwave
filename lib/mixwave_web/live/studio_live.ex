defmodule MixwaveWeb.StudioLive do
  @moduledoc """
  Placeholder. The real studio shell lands in the next commit:
  presence sidebar, instrument tabs, latency-hint footer, and the
  Vue island slot for the active instrument pad.
  """
  use MixwaveWeb, :live_view

  @impl true
  def mount(_params, _session, socket), do: {:ok, socket}

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash}>
      <.header>
        Studio
        <:subtitle>
          {if @current_user, do: "you are #{@current_user.display_name}", else: "anonymous"}
        </:subtitle>
      </.header>

      <p class="text-muted-foreground">
        The studio is being scaffolded. Real-time jam coming next.
      </p>
    </Layouts.app>
    """
  end
end
