defmodule MixchambWeb.LandingLive do
  @moduledoc """
  The "/" page. Pre-jam landing — explains the chamber model and
  offers a single primary action ("Create a chamber") that creates
  a row, generates a fresh slug, and pushes the user into the
  chamber's URL.
  """
  use MixchambWeb, :live_view

  alias Mixchamb.Chambers

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_event("create_chamber", params, socket) do
    user = socket.assigns.current_user
    activity = Map.get(params, "activity", "music")

    case Chambers.create_chamber(user.id, activity) do
      {:ok, chamber} ->
        {:noreply, push_navigate(socket, to: ~p"/chamber/#{chamber.slug}")}

      {:error, _changeset} ->
        # Slug collision is the only realistic failure here, and
        # it's vanishingly unlikely. Surface a generic flash and
        # let the user try again. (Invalid activity also lands
        # here, but it's a programming bug — the UI only emits
        # values from Chamber.activities/0.)
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
      <%!-- Ambient brand wash. A very faint radial gradient sitting
           behind the hero, tinted in the brick-stack logo's pink →
           cyan → green stops. Visually lifts the page off pure
           charcoal without drawing the eye away from the cards. --%>
      <div
        aria-hidden="true"
        class="pointer-events-none fixed inset-0 -z-10 brand-wash"
      >
      </div>

      <div class="-mx-4 sm:-mx-6 lg:-mx-8 -my-10 px-4 sm:px-6 lg:px-8 py-16 min-h-[calc(100dvh-3.5rem)] flex items-center justify-center">
        <div class="w-full max-w-5xl space-y-10">
          <div class="text-center space-y-3">
            <%!-- Logo with a soft brand-coloured glow underneath so
                 it reads as the lit centre of the page instead of a
                 dim chip on a flat background. --%>
            <div class="relative mx-auto w-fit">
              <div
                aria-hidden="true"
                class="absolute inset-0 -m-6 rounded-full blur-2xl opacity-60 brand-glow"
              >
              </div>
              <img src={~p"/images/logo.svg"} alt="" class="relative size-16" />
            </div>
            <h1 class="text-3xl sm:text-4xl font-bold tracking-tight font-display brand-gradient-text">
              Pick a chamber
            </h1>
            <p class="text-sm text-muted-foreground">
              Realtime collaborative activities. Jam together, plan together, or just hang out — pick one to start.
            </p>
          </div>

          <div class="grid sm:grid-cols-2 lg:grid-cols-3 gap-4">
            <%!-- Chaos Chamber: public, always-on, anyone can join.
                  Music-only by design — see BRAINSTORM-v4.md §5.2. --%>
            <button
              phx-click="enter_chaos"
              class="text-left rounded-2xl border bg-card hover:bg-accent transition-colors p-6 cursor-pointer space-y-3 group"
            >
              <div class="flex items-center gap-2">
                <span class="size-2.5 rounded-full bg-accent-drums"></span>
                <span class="text-xs uppercase tracking-wider text-muted-foreground">
                  Public · Music
                </span>
              </div>
              <h2 class="text-2xl font-bold tracking-tight font-display">
                Chaos chamber
              </h2>
              <p class="text-sm text-muted-foreground">
                Public always-on jam. Anyone can wander in, anyone can leave. Sound is shared with everyone here right now — expect overlap, expect surprises.
              </p>
              <div class="pt-2 text-sm font-medium text-foreground inline-flex items-center gap-1">
                Enter chaos
                <.icon
                  name="hero-arrow-right-mini"
                  class="size-4 transition-transform group-hover:translate-x-0.5"
                />
              </div>
            </button>

            <%!-- Music chamber: private, link-only. Activity = "music". --%>
            <button
              phx-click="create_chamber"
              phx-value-activity="music"
              class="text-left rounded-2xl border bg-card hover:bg-accent transition-colors p-6 cursor-pointer space-y-3 group"
            >
              <div class="flex items-center gap-2">
                <span class="size-2.5 rounded-full bg-accent-pad"></span>
                <span class="text-xs uppercase tracking-wider text-muted-foreground">
                  Private · Music
                </span>
              </div>
              <h2 class="text-2xl font-bold tracking-tight font-display">
                Music chamber
              </h2>
              <p class="text-sm text-muted-foreground">
                Spin up a private jam. Share the link with whoever you want to play with — anyone with it can join, nobody else can find it. Closes if empty for 30 minutes.
              </p>
              <div class="pt-2 text-sm font-medium text-foreground inline-flex items-center gap-1">
                Create music chamber
                <.icon
                  name="hero-arrow-right-mini"
                  class="size-4 transition-transform group-hover:translate-x-0.5"
                />
              </div>
            </button>

            <%!-- Planning poker: private, link-only. Activity = "poker".
                  Default deck is Fibonacci; host can switch via the
                  in-chamber dropdown before any votes are cast. --%>
            <button
              phx-click="create_chamber"
              phx-value-activity="poker"
              class="text-left rounded-2xl border bg-card hover:bg-accent transition-colors p-6 cursor-pointer space-y-3 group"
            >
              <div class="flex items-center gap-2">
                <span class="size-2.5 rounded-full bg-accent-keyboard"></span>
                <span class="text-xs uppercase tracking-wider text-muted-foreground">
                  Private · Planning
                </span>
              </div>
              <h2 class="text-2xl font-bold tracking-tight font-display">
                Planning poker
              </h2>
              <p class="text-sm text-muted-foreground">
                Estimate together. Deal cards, hide them until reveal, see the spread, re-vote if you need to. Share the link, the team votes, you decide.
              </p>
              <div class="pt-2 text-sm font-medium text-foreground inline-flex items-center gap-1">
                Start poker session
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
