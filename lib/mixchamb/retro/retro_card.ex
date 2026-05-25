defmodule Mixchamb.Retro.RetroCard do
  @moduledoc """
  One brainstormed card. Author-owned, 280-char cap, alias-tagged.
  Editable only during `:brainstorm` (spec §3 — editability gate
  table). `vote_count` is denormalised from the ephemeral vote
  map held in `Mixchamb.Chambers.Server` and materialised on
  phase exit `:voting → :discuss`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_body 280

  @derive {LiveVue.Encoder,
           only: [
             :id,
             :retro_session_id,
             :retro_column_id,
             :body,
             :author_user_id,
             :author_alias,
             :author_display_name,
             :vote_count
           ]}

  schema "retro_cards" do
    field :body, :string
    field :author_alias, :string
    field :author_display_name, :string
    field :vote_count, :integer, default: 0

    belongs_to :session, Mixchamb.Retro.RetroSession, foreign_key: :retro_session_id
    belongs_to :column, Mixchamb.Retro.RetroColumn, foreign_key: :retro_column_id
    belongs_to :author, Mixchamb.Accounts.AnonymousUser, foreign_key: :author_user_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def creation_changeset(card, attrs) do
    card
    |> cast(attrs, [
      :retro_session_id,
      :retro_column_id,
      :body,
      :author_user_id,
      :author_alias,
      :author_display_name
    ])
    |> validate_required([:retro_session_id, :retro_column_id, :body, :author_alias])
    |> update_change(:body, &normalize_body/1)
    |> validate_length(:body, min: 1, max: @max_body)
  end

  @doc false
  def body_changeset(card, attrs) do
    card
    |> cast(attrs, [:body])
    |> validate_required([:body])
    |> update_change(:body, &normalize_body/1)
    |> validate_length(:body, min: 1, max: @max_body)
  end

  @doc false
  def vote_count_changeset(card, attrs) do
    card
    |> cast(attrs, [:vote_count])
    |> validate_required([:vote_count])
    |> validate_number(:vote_count, greater_than_or_equal_to: 0)
  end

  defp normalize_body(nil), do: nil
  defp normalize_body(body) when is_binary(body), do: String.trim(body)
end
