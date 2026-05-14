defmodule MixwaveWeb.Layouts do
  @moduledoc """
  Layout components for the application shell.

  Styling uses shadcn-vue's design tokens (bg-background, text-foreground,
  border, etc.). The same tokens are wired up in app.css so the HEEX
  side and the Vue island side share one design language.
  """
  use MixwaveWeb, :html

  embed_templates "layouts/*"

  @doc """
  Renders the app layout: top header + page outlet.

  `width` controls the inner container's max width:
    * `:default` — `max-w-3xl` (chamber + landing pages, narrow & focused)
    * `:wide`    — `max-w-[1536px]` (admin tables; comfortable on
                    laptops, no longer crushed at 3xl)
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"

  attr :current_scope, :map,
    default: nil,
    doc: "the current [scope](https://hexdocs.pm/phoenix/scopes.html)"

  attr :width, :atom, default: :default, values: [:default, :wide]

  attr :banner, :any,
    default: nil,
    doc: "active system banner, set by the BannerHook on_mount"

  attr :draining?, :boolean,
    default: false,
    doc: "true when the host node is shutting down, set by BannerHook"

  slot :inner_block, required: true

  def app(assigns) do
    ~H"""
    <%!-- Drain warning. Wins over the admin banner because it's
         a "your connection is about to die" signal — render it
         first so it sits at the very top. --%>
    <div
      :if={@draining?}
      class="bg-amber-500/15 border-b border-amber-500/40 text-foreground"
    >
      <div class="mx-auto max-w-5xl flex items-start gap-3 px-4 sm:px-6 lg:px-8 py-2">
        <.icon
          name="hero-arrow-path-mini"
          class="size-4 mt-0.5 shrink-0 text-amber-500 motion-safe:animate-spin"
        />
        <p class="flex-1 text-sm leading-snug">
          Server restarting — you'll briefly disconnect and the page will reconnect automatically.
        </p>
      </div>
    </div>

    <%!-- Admin-broadcast banner. Rendered above the header so it
         doesn't get scrolled off; auto-hides as soon as the row
         expires (BannerHook pushes nil on the PubSub topic). --%>
    <div
      :if={@banner}
      class="bg-primary/15 border-b border-primary/30 text-foreground"
    >
      <div class="mx-auto max-w-5xl flex items-start gap-3 px-4 sm:px-6 lg:px-8 py-2">
        <.icon name="hero-megaphone-mini" class="size-4 mt-0.5 shrink-0 text-primary" />
        <p class="flex-1 text-sm leading-snug">{@banner.message}</p>
      </div>
    </div>

    <header class="border-b">
      <div class="mx-auto max-w-5xl flex items-center gap-6 px-4 sm:px-6 lg:px-8 py-3">
        <a href="/" class="flex items-center gap-2 hover:opacity-80">
          <img src={static_url(MixwaveWeb.Endpoint, ~p"/images/logo.svg")} width="32" />
          <span class="text-base font-bold tracking-tight font-display">mixwave</span>
        </a>
        <span class="text-xs text-muted-foreground">real-time jam chambers</span>
        <div class="ml-auto flex items-center gap-2">
          <.theme_toggle />
        </div>
      </div>
    </header>

    <main class="px-4 py-10 sm:px-6 lg:px-8">
      <div class={[
        "mx-auto space-y-4",
        @width == :default && "max-w-3xl",
        @width == :wide && "max-w-[1536px]"
      ]}>
        {render_slot(@inner_block)}
      </div>
    </main>

    <.flash_group flash={@flash} />
    """
  end

  @doc """
  Shows the flash group with standard titles and content.
  """
  attr :flash, :map, required: true, doc: "the map of flash messages"
  attr :id, :string, default: "flash-group", doc: "the optional id of flash container"

  def flash_group(assigns) do
    ~H"""
    <div id={@id} aria-live="polite">
      <.flash kind={:info} flash={@flash} />
      <.flash kind={:error} flash={@flash} />

      <.flash
        id="client-error"
        kind={:error}
        title={gettext("We can't find the internet")}
        phx-disconnected={show(".phx-client-error #client-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#client-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>

      <.flash
        id="server-error"
        kind={:error}
        title={gettext("Something went wrong!")}
        phx-disconnected={show(".phx-server-error #server-error") |> JS.remove_attribute("hidden")}
        phx-connected={hide("#server-error") |> JS.set_attribute({"hidden", ""})}
        hidden
      >
        {gettext("Attempting to reconnect")}
        <.icon name="hero-arrow-path" class="ml-1 size-3 motion-safe:animate-spin" />
      </.flash>
    </div>
    """
  end

  @doc """
  System / light / dark theme toggle. The actual theme application is
  handled by an inline script in `root.html.heex` that toggles a `dark`
  class on `<html>`. These buttons just dispatch the `phx:set-theme`
  event.
  """
  def theme_toggle(assigns) do
    ~H"""
    <div class="inline-flex items-center rounded-md border bg-card p-0.5">
      <button
        class="inline-flex items-center justify-center rounded-sm p-1.5 text-muted-foreground hover:bg-accent hover:text-accent-foreground cursor-pointer"
        title="Match system theme"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="system"
      >
        <.icon name="hero-computer-desktop-micro" class="size-4" />
      </button>
      <button
        class="inline-flex items-center justify-center rounded-sm p-1.5 text-muted-foreground hover:bg-accent hover:text-accent-foreground cursor-pointer"
        title="Light theme"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="light"
      >
        <.icon name="hero-sun-micro" class="size-4" />
      </button>
      <button
        class="inline-flex items-center justify-center rounded-sm p-1.5 text-muted-foreground hover:bg-accent hover:text-accent-foreground cursor-pointer"
        title="Dark theme"
        phx-click={JS.dispatch("phx:set-theme")}
        data-phx-theme="dark"
      >
        <.icon name="hero-moon-micro" class="size-4" />
      </button>
    </div>
    """
  end
end
