defmodule MixwaveWeb.Router do
  use MixwaveWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MixwaveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MixwaveWeb.Plugs.EnsureAnonUser
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  # Admin gate: same browser stack but with HTTP Basic Auth in
  # front. Username + password come from runtime config (env vars
  # in prod). The pipeline is only attached to the /admin scope —
  # the rest of the app stays anonymous.
  pipeline :admin do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {MixwaveWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
    plug MixwaveWeb.Plugs.EnsureAnonUser
    plug MixwaveWeb.Plugs.AdminAuth
  end

  scope "/", MixwaveWeb do
    pipe_through :browser

    live_session :default, on_mount: {MixwaveWeb.UserAuth, :current_user} do
      live "/", LandingLive
      live "/chamber/:slug", ChamberLive
    end
  end

  scope "/admin", MixwaveWeb.Admin, as: :admin do
    pipe_through :admin

    live_session :admin, on_mount: {MixwaveWeb.UserAuth, :current_user} do
      live "/", DashboardLive, :index
      live "/system", SystemLive, :index
      live "/chambers", ChambersLive, :index
      live "/users", UsersLive, :index
      live "/activity", ActivityLive, :index
      live "/sweepers", SweepersLive, :index
    end
  end

  # Other scopes may use custom stacks.
  # scope "/api", MixwaveWeb do
  #   pipe_through :api
  # end

  # Enable LiveDashboard in development
  if Application.compile_env(:mixwave, :dev_routes) do
    # If you want to use the LiveDashboard in production, you should put
    # it behind authentication and allow only admins to access it.
    # If your application does not have an admins-only section yet,
    # you can use Plug.BasicAuth to set up some basic authentication
    # as long as you are also using SSL (which you should anyway).
    import Phoenix.LiveDashboard.Router

    scope "/dev" do
      pipe_through :browser

      live_dashboard "/dashboard", metrics: MixwaveWeb.Telemetry
    end
  end
end
