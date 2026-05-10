defmodule Mixwave.Release do
  @moduledoc """
  Release tasks. Invoked from `bin/mixwave eval` (or from the
  release-overlay scripts at `rel/overlays/bin/migrate` /
  `rollback`) so we can run Ecto migrations without packaging
  Mix into the release image.

  In a release, Mix is *not* available — `mix ecto.migrate`
  doesn't work after `mix release`. Instead we use
  `Ecto.Migrator` directly. The `load_app/0` helper makes sure
  the application is started enough that the Repo can connect.
  """
  @app :mixwave

  def migrate do
    load_app()

    for repo <- repos() do
      {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :up, all: true))
    end
  end

  def rollback(repo, version) do
    load_app()
    {:ok, _, _} = Ecto.Migrator.with_repo(repo, &Ecto.Migrator.run(&1, :down, to: version))
  end

  defp repos do
    Application.fetch_env!(@app, :ecto_repos)
  end

  defp load_app do
    Application.load(@app)
  end
end
