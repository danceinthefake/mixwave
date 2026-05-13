defmodule Mixwave.Repo.Migrations.AddAliasToAnonymousUsers do
  use Ecto.Migration

  def change do
    alter table(:anonymous_users) do
      # User-set nickname. Nullable — most users never set one, and
      # the auto-generated `display_name` (noun-adj-NN) stays the
      # canonical identifier shown next to the alias in the UI.
      add :alias, :text
    end
  end
end
