defmodule Mixwave.Repo.Migrations.CreateComments do
  use Ecto.Migration

  def change do
    create table(:comments, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :song_id,
          references(:songs, type: :binary_id, on_delete: :delete_all),
          null: false

      add :user_id,
          references(:anonymous_users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :body, :text, null: false

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:comments, [:song_id, :inserted_at])
    create index(:comments, [:user_id])
  end
end
