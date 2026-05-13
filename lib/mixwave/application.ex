defmodule Mixwave.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    # Public ETS counter for chamber-server restart counts. Each
    # `Mixwave.Chambers.Server.init/1` bumps its slug's entry; the
    # supervisor LV reads it for the per-chamber Restarts column.
    # Initialised here so it exists before the first chamber starts.
    :ets.new(:chamber_restart_counts, [:set, :public, :named_table, write_concurrency: true])

    # Public ETS bucket store for the note-event rate limiter
    # (one row per {scope, user, slug}). Created here so the first
    # incoming LV `note` event finds it ready.
    :ets.new(Mixwave.RateLimiter.table(), [
      :set,
      :public,
      :named_table,
      write_concurrency: true
    ])

    children = [
      MixwaveWeb.Telemetry,
      Mixwave.Repo,
      {DNSCluster, query: Application.get_env(:mixwave, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Mixwave.PubSub},
      # Hourly tick deletes anonymous users idle for more than 24 h.
      Mixwave.Accounts.Sweeper,
      # Hourly tick deletes chambers idle for more than 24 h.
      Mixwave.Chambers.Sweeper,
      # Looks up per-chamber GenServers by slug.
      {Registry, keys: :unique, name: Mixwave.Chambers.Registry},
      # Spawns one Mixwave.Chambers.Server per active chamber. Each
      # holds the chamber's recent-events buffer for join-time replay.
      {DynamicSupervisor, name: Mixwave.Chambers.Supervisor, strategy: :one_for_one},
      # Counts how many times each supervised process has restarted.
      Mixwave.RestartWatcher,
      # Subscribes to custom mixwave telemetry events and rolls up
      # per-process counters for the admin Dashboard. Started early
      # so it never misses an event from a chamber or sweeper.
      Mixwave.Telemetry.Counters,
      # Tracks who's in the chamber + their selected instrument.
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
