defmodule MixwaveWeb.Admin.Layouts do
  @moduledoc """
  Shared shell for the `/admin` LiveViews. Renders a left sidebar
  with one entry per tab and a main content area for the page's
  own header + body.

  Tabs are listed once here so adding/removing one is a single-line
  change. The active item is matched against the current LV's
  `@socket.view` module (each tab has a single LV), so deep-linking
  to `/admin/chambers/...` keeps the right tab highlighted.
  """
  use MixwaveWeb, :html

  @tabs [
    %{
      label: "Dashboard",
      path: "/admin",
      view: MixwaveWeb.Admin.DashboardLive,
      icon: "hero-squares-2x2"
    },
    %{
      label: "System",
      path: "/admin/system",
      view: MixwaveWeb.Admin.SystemLive,
      icon: "hero-cpu-chip"
    },
    %{
      label: "Chambers",
      path: "/admin/chambers",
      view: MixwaveWeb.Admin.ChambersLive,
      icon: "hero-cube"
    },
    %{label: "Users", path: "/admin/users", view: MixwaveWeb.Admin.UsersLive, icon: "hero-users"},
    %{
      label: "Activity",
      path: "/admin/activity",
      view: MixwaveWeb.Admin.ActivityLive,
      icon: "hero-bolt"
    },
    %{
      label: "Sweepers",
      path: "/admin/sweepers",
      view: MixwaveWeb.Admin.SweepersLive,
      icon: "hero-trash"
    },
    %{
      label: "Cluster",
      path: "/admin/cluster",
      view: MixwaveWeb.Admin.ClusterLive,
      icon: "hero-globe-alt"
    },
    %{
      label: "Ops",
      path: "/admin/ops",
      view: MixwaveWeb.Admin.OpsLive,
      icon: "hero-megaphone"
    },
    %{
      label: "Rate limits",
      path: "/admin/rate-limits",
      view: MixwaveWeb.Admin.RateLimitsLive,
      icon: "hero-no-symbol"
    },
    %{
      label: "Health",
      path: "/admin/health",
      view: MixwaveWeb.Admin.HealthLive,
      icon: "hero-heart"
    }
  ]

  @doc """
  Wraps an admin page. Pass `current_view: @socket.view` so the
  sidebar can highlight the active tab; everything else lives in
  the inner block.
  """
  attr :current_view, :atom, required: true
  attr :flash, :map, default: %{}
  attr :banner, :any, default: nil
  attr :draining?, :boolean, default: false
  slot :inner_block, required: true

  def admin_shell(assigns) do
    assigns = assign(assigns, :tabs, @tabs)

    ~H"""
    <Layouts.app flash={@flash} width={:wide} banner={@banner} draining?={@draining?}>
      <div class="grid grid-cols-1 lg:grid-cols-[14rem_1fr] gap-6">
        <aside class="lg:sticky lg:top-4 lg:self-start">
          <div class="rounded-xl border bg-card p-2">
            <div class="px-3 py-2 text-xs font-semibold uppercase tracking-wider text-muted-foreground">
              Admin
            </div>
            <nav class="flex flex-col gap-0.5">
              <.link
                :for={t <- @tabs}
                navigate={t.path}
                class={[
                  "flex items-center gap-2 px-3 py-2 rounded-md text-sm transition-colors",
                  @current_view == t.view &&
                    "bg-primary/10 text-primary font-medium",
                  @current_view != t.view &&
                    "text-muted-foreground hover:bg-accent hover:text-foreground"
                ]}
              >
                <.icon name={t.icon} class="size-4 shrink-0" />
                <span>{t.label}</span>
              </.link>
            </nav>
          </div>
          <div class="mt-4 px-3 space-y-2 text-[11px] text-muted-foreground">
            <p>
              <.link navigate={~p"/"} class="underline">Back to app</.link>
            </p>
            <.link
              href={~p"/admin/logout"}
              method="delete"
              class="inline-flex items-center gap-1 underline hover:text-foreground"
            >
              <.icon name="hero-arrow-right-on-rectangle-mini" class="size-3.5" /> Log out
            </.link>
          </div>
        </aside>

        <main class="min-w-0">
          {render_slot(@inner_block)}
        </main>
      </div>
    </Layouts.app>
    """
  end
end
