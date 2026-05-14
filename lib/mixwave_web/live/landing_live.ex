defmodule MixwaveWeb.LandingLive do
  @moduledoc """
  The "/" page. Pre-jam landing — explains the chamber model and
  offers a single primary action ("Create a chamber") that creates
  a row, generates a fresh slug, and pushes the user into the
  chamber's URL.
  """
  use MixwaveWeb, :live_view

  alias Mixwave.Chambers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("create_chamber", _params, socket) do
    user = socket.assigns.current_user

    case Chambers.create_chamber(user.id) do
      {:ok, chamber} ->
        {:noreply, push_navigate(socket, to: ~p"/chamber/#{chamber.slug}")}

      {:error, _changeset} ->
        # Slug collision is the only realistic failure here, and
        # it's vanishingly unlikely. Surface a generic flash and
        # let the user try again.
        {:noreply, put_flash(socket, :error, "Couldn't create the chamber. Try again.")}
    end
  end

  @impl true
  def handle_event("enter_chaos", _params, socket) do
    # Lazily seed the public Chaos Chamber on first click. Subsequent
    # clicks find the existing row.
    case Chambers.ensure_chaos_chamber() do
      {:ok, chamber} ->
        {:noreply, push_navigate(socket, to: ~p"/chamber/#{chamber.slug}")}

      {:error, _changeset} ->
        {:noreply, put_flash(socket, :error, "Couldn't enter the chaos chamber.")}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layouts.app flash={@flash} banner={assigns[:banner]} draining?={assigns[:draining?] || false}>
      <div class="-mx-4 sm:-mx-6 lg:-mx-8 -my-10 px-4 sm:px-6 lg:px-8 py-16 min-h-[calc(100dvh-3.5rem)] flex items-center justify-center">
        <div class="w-full max-w-3xl space-y-10">
          <div class="text-center space-y-3">
            <img src={~p"/images/logo.svg"} alt="" class="size-16 mx-auto" />
            <h1 class="text-3xl sm:text-4xl font-bold tracking-tight font-display">
              Pick a chamber
            </h1>
            <p class="text-sm text-muted-foreground">
              Two ways to play: jump into the public chamber or open a private one.
            </p>
          </div>

          <div class="grid sm:grid-cols-2 gap-4">
            <%!-- Chaos Chamber: public, always-on, anyone can join. --%>
            <button
              phx-click="enter_chaos"
              class="text-left rounded-2xl border bg-card hover:bg-accent transition-colors p-6 cursor-pointer space-y-3 group"
            >
              <div class="flex items-center gap-2">
                <span class="size-2.5 rounded-full bg-accent-drums"></span>
                <span class="text-xs uppercase tracking-wider text-muted-foreground">
                  Public
                </span>
              </div>
              <h2 class="text-2xl font-bold tracking-tight font-display">
                Chaos chamber
              </h2>
              <p class="text-sm text-muted-foreground">
                Public always-on chamber. Anyone can wander in, anyone can leave. Sound is shared with everyone here right now — expect overlap, expect surprises.
              </p>
              <div class="pt-2 text-sm font-medium text-foreground inline-flex items-center gap-1">
                Enter chaos
                <.icon
                  name="hero-arrow-right-mini"
                  class="size-4 transition-transform group-hover:translate-x-0.5"
                />
              </div>
            </button>

            <%!-- Secret Chamber: private, link-only, you create it. --%>
            <button
              phx-click="create_chamber"
              class="text-left rounded-2xl border bg-card hover:bg-accent transition-colors p-6 cursor-pointer space-y-3 group"
            >
              <div class="flex items-center gap-2">
                <span class="size-2.5 rounded-full bg-accent-pad"></span>
                <span class="text-xs uppercase tracking-wider text-muted-foreground">
                  Private
                </span>
              </div>
              <h2 class="text-2xl font-bold tracking-tight font-display">
                Secret chamber
              </h2>
              <p class="text-sm text-muted-foreground">
                Spin up a private chamber. Share the link with whoever you want to play with — anyone with it can join, nobody else can find it. Closes if empty for 30 minutes.
              </p>
              <div class="pt-2 text-sm font-medium text-foreground inline-flex items-center gap-1">
                Create secret chamber
                <.icon
                  name="hero-arrow-right-mini"
                  class="size-4 transition-transform group-hover:translate-x-0.5"
                />
              </div>
            </button>
          </div>
        </div>
      </div>
    </Layouts.app>
    """
  end
end
