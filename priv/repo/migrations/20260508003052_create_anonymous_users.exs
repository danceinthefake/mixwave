defmodule Mixwave.Repo.Migrations.CreateAnonymousUsers do
  use Ecto.Migration

  def change do
    create table(:anonymous_users, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :display_name, :text, null: false
      add :last_active_at, :utc_datetime, null: false, default: fragment("now()")

      timestamps(type: :utc_datetime, updated_at: false)
    end

    # The sweeper deletes anonymous users idle for more than 24 hours.
    # Indexed so that scan stays fast as the row count grows.
    create index(:anonymous_users, [:last_active_at])
  end
end
