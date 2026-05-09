defmodule Mixwave.Chambers.Chamber do
  @moduledoc """
  A secret chamber — a link-only private room.

  Created by an `Mixwave.Accounts.AnonymousUser`; identified by an
  unguessable `slug` that's also the URL segment users visit. The
  `activated_at` field flips from NULL to a timestamp the first
  time someone other than the creator joins; while it's NULL the
  chamber is in its 5-minute grace window and may be auto-deleted
  by `Mixwave.Studio.Chamber`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chambers" do
    field :slug, :string
    field :activated_at, :utc_datetime
    field :title, :string
    field :last_activity_at, :utc_datetime

    belongs_to :creator, Mixwave.Accounts.AnonymousUser, foreign_key: :creator_user_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def creation_changeset(chamber, attrs) do
    chamber
    |> cast(attrs, [:slug, :creator_user_id])
    |> validate_required([:slug, :creator_user_id])
    |> unique_constraint(:slug)
  end

  @doc false
  def activation_changeset(chamber) do
    chamber
    |> change(activated_at: DateTime.utc_now() |> DateTime.truncate(:second))
  end

  @doc false
  def title_changeset(chamber, attrs) do
    chamber
    |> cast(attrs, [:title])
    |> update_change(:title, &normalize_title/1)
    |> validate_length(:title, max: 80)
  end

  # Treat empty / whitespace-only strings as "no title set" so the
  # UI's nil-fallback path covers users clearing the field.
  defp normalize_title(nil), do: nil

  defp normalize_title(title) when is_binary(title) do
    case String.trim(title) do
      "" -> nil
      trimmed -> trimmed
    end
  end
end
