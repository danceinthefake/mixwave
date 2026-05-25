defmodule Mixchamb.Repo.Migrations.AddAuthorDisplayNameToRetroCards do
  use Ecto.Migration

  # Spec §3 calls for cards to be alias-tagged in the same
  # two-piece pattern poker reveal uses ("Brave Otter 12 ·
  # alex"). Pre-fix we only stored a single `author_alias`
  # field (snapshot of `user.alias || user.display_name`), so we
  # had no way to render both halves. New column carries the
  # noun-adj-NN handle separately; nullable because existing
  # rows can't be backfilled deterministically (we don't know
  # which side of the OR each snapshot came from).
  def change do
    alter table(:retro_cards) do
      add :author_display_name, :string
    end
  end
end
