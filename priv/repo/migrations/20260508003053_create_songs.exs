defmodule Mixwave.Repo.Migrations.CreateSongs do
  use Ecto.Migration

  def change do
    create table(:songs, primary_key: false) do
      add :id, :binary_id, primary_key: true, default: fragment("gen_random_uuid()")

      add :user_id,
          references(:anonymous_users, type: :binary_id, on_delete: :delete_all),
          null: false

      add :title, :text, null: false
      add :description, :text
      add :genre, :text
      add :storage_key, :text, null: false
      add :duration_s, :real
      # Pre-computed waveform peaks so the Vue island can render the
      # waveform without re-decoding the audio on every page load.
      add :waveform_peaks, {:array, :real}

      timestamps(type: :utc_datetime, updated_at: false)
    end

    create index(:songs, [:user_id])
    create index(:songs, [:inserted_at])
  end
end
