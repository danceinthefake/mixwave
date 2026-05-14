defmodule Mixwave.Repo.Migrations.CreateAdmins do
  use Ecto.Migration

  def change do
    # citext makes the unique username index case-insensitive
    # without needing a functional index.
    execute "CREATE EXTENSION IF NOT EXISTS citext", "DROP EXTENSION IF EXISTS citext"

    # Per-user admin accounts. The login flow falls back to the
    # env ADMIN_USER/ADMIN_PASSWORD if no DB row matches — see
    # AdminSessionController. That keeps a break-glass route in
    # case every admin loses their password.
    create table(:admins, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")
      add :username, :citext, null: false
      add :password_hash, :text, null: false
      add :last_login_at, :utc_datetime_usec

      timestamps(type: :utc_datetime)
    end

    create unique_index(:admins, [:username])
  end
end
