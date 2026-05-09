defmodule Mixwave.Repo.Migrations.AddLastActivityAtToChambers do
  use Ecto.Migration

  def change do
    alter table(:chambers) do
      # Bumped by the per-chamber GenServer once a minute when any
      # notes were played in that minute. The sweeper deletes
      # chambers whose last_activity_at is more than 24h old.
      add :last_activity_at, :utc_datetime, null: false, default: fragment("now()")
    end

    # The sweeper does an indexed range scan; without this it'd be
    # a sequential scan of every chamber on every sweep.
    create index(:chambers, [:last_activity_at])
  end
end
