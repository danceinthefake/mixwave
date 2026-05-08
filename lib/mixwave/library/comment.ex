defmodule Mixwave.Library.Comment do
  @moduledoc """
  A comment on a song. Comments are not editable — only created or
  deleted (cascade with the parent song or the commenting user).
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "comments" do
    field :body, :string

    belongs_to :song, Mixwave.Library.Song
    belongs_to :user, Mixwave.Accounts.AnonymousUser

    timestamps(type: :utc_datetime, updated_at: false)
  end

  def creation_changeset(comment, attrs) do
    comment
    |> cast(attrs, [:song_id, :user_id, :body])
    |> validate_required([:song_id, :user_id, :body])
    |> validate_length(:body, min: 1, max: 1_000)
    |> assoc_constraint(:song)
    |> assoc_constraint(:user)
  end
end
