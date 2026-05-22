defmodule Mixchamb.Repo.Migrations.AddActivityToChambers do
  use Ecto.Migration

  def change do
    alter table(:chambers) do
      # Which activity the chamber is currently running — music,
      # poker (added with v4 planning-poker MVP), and future
      # activities like standup / retro / icebreaker. Default
      # `"music"` so every existing row (the chaos chamber + all
      # user-created music chambers) keeps working without a
      # backfill. Validation of allowed values lives in the
      # Chamber schema's `@activities` list.
      add :activity, :string, null: false, default: "music"
    end
  end
end
