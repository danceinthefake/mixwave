defmodule Mixwave.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      MixwaveWeb.Telemetry,
      Mixwave.Repo,
      {DNSCluster, query: Application.get_env(:mixwave, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mixwave.PubSub},
      # Anon-user sweeper: hourly tick deletes users idle > 24h.
      # First flagship OTP demo — supervised, restartable, idempotent.
      Mixwave.Accounts.Sweeper,
      # Studio room: supervised GenServer holding recent note events
      # for join-time replay. Second flagship OTP demo — kill it in
      # the v2 chaos board, watch it restart, jam resumes.
      Mixwave.Studio.Room,
      # Phoenix.Presence module — tracks who's in the studio.
      MixwaveWeb.Presence,
      # Start to serve requests, typically the last entry
      MixwaveWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: Mixwave.Supervisor]
    children =
      children ++
        if(Application.get_env(:live_vue, :ssr_module) == LiveVue.SSR.QuickBEAM,
          do: [LiveVue.SSR.QuickBEAM],
          else: []
        )

    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    MixwaveWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
