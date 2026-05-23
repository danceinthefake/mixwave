defmodule Mixchamb.Repo.Migrations.CreateChamberVisits do
  use Ecto.Migration

  # Tracks "this user has been in this chamber", upserted on each
  # ChamberLive mount. Drives the Resume section on the landing
  # page. Both FKs cascade-delete so when a chamber is reaped
  # (30-min idle) or a user is reaped (24-h idle), the matching
  # visit rows go with them — no zombie listings.
  def change do
    create table(:chamber_visits, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :user_id,
          references(:anonymous_users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :chamber_id,
          references(:chambers, type: :binary_id, on_delete: :delete_all),
          null: false

      add :last_visited_at, :utc_datetime, null: false
    end

    # One row per (user, chamber). Drives the upsert + the
    # "newest visit wins" semantics.
    create unique_index(:chamber_visits, [:user_id, :chamber_id])
    # Used for the recent-visits query (where user_id = ? order by last_visited_at desc).
    create index(:chamber_visits, [:user_id, :last_visited_at])
  end
end
