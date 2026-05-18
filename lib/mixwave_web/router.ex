defmodule MixwaveWeb.Router do
  use MixwaveWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MixwaveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MixwaveWeb.Plugs.SecurityHeaders
    plug MixwaveWeb.Plugs.EnsureAnonUser
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Admin gate: same browser stack with the AdminAuth plug appended.
  # Used for the gated `/admin/*` LV scope. Login + logout sit in
  # the regular :browser pipeline so an unauthenticated user can
  # actually reach the form.
  pipeline :admin do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MixwaveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MixwaveWeb.Plugs.SecurityHeaders
    plug MixwaveWeb.Plugs.EnsureAnonUser
    plug MixwaveWeb.Plugs.AdminAuth
  end

  scope "/", MixwaveWeb do
    pipe_through :browser

    live_session :default,
      on_mount: [
        {MixwaveWeb.UserAuth, :current_user},
        {MixwaveWeb.Live.BannerHook, :default}
      ] do
      live "/", LandingLive
      live "/chamber/:slug", ChamberLive
    end

    # Admin login / logout — ungated so the user can reach the
    # form without already being authenticated.
    get "/admin/login", AdminSessionController, :new
    post "/admin/login", AdminSessionController, :create
    delete "/admin/logout", AdminSessionController, :delete
  end

  scope "/admin", MixwaveWeb.Admin, as: :admin do
    pipe_through :admin

    live_session :admin,
      on_mount: [
        {MixwaveWeb.UserAuth, :current_user},
        {MixwaveWeb.UserAuth, :current_admin},
        {MixwaveWeb.Live.BannerHook, :default}
      ] do
      live "/", DashboardLive, :index
      live "/system", SystemLive, :index
      live "/chambers", ChambersLive, :index
      live "/chambers/:slug", ChamberDetailLive, :show
      live "/rate-limits", RateLimitsLive, :index
      live "/health", HealthLive, :index
      live "/users", UsersLive, :index
      live "/activity", ActivityLive, :index
      live "/sweepers", SweepersLive, :index
      live "/cluster", ClusterLive, :index
      live "/ops", OpsLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", MixwaveWeb do
  #   pipe_through :api
  # end

  # Phoenix LiveDashboard — BEAM internals, telemetry charts, ETS
  # tables, process picker. Behind the same :admin pipeline as the
  # rest of /admin so it stays gated in prod (and uses admin/dev
  # creds locally).
  scope "/admin" do
    pipe_through :admin

    import Phoenix.LiveDashboard.Router

    live_dashboard "/beam",
      metrics: MixwaveWeb.Telemetry,
      ecto_repos: [Mixwave.Repo]
  end
end
