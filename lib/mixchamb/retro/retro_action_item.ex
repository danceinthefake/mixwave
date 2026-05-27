defmodule Mixchamb.Retro.RetroActionItem do
  @moduledoc """
  Action item captured during `:discuss`. Optionally tied to
  a source card (spec §6). `assignee_alias` is free text rather
  than an FK — teams sometimes assign to people who aren't in
  the chamber.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @max_body 280
  @max_assignee 80

  @derive {LiveVue.Encoder,
           only: [
             :id,
             :retro_session_id,
             :source_card_id,
             :body,
             :assignee_alias,
             :due_date,
             :completed
           ]}

  schema "retro_action_items" do
    field :body, :string
    field :assignee_alias, :string
    field :due_date, :date
    field :completed, :boolean, default: false

    belongs_to :session, Mixchamb.Retro.RetroSession, foreign_key: :retro_session_id

    belongs_to :source_card, Mixchamb.Retro.RetroCard,
      foreign_key: :source_card_id,
      type: :binary_id

    belongs_to :creator, Mixchamb.Accounts.AnonymousUser,
      foreign_key: :created_by_user_id,
      type: :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def creation_changeset(action, attrs) do
    action
    |> cast(attrs, [
      :retro_session_id,
      :source_card_id,
      :body,
      :assignee_alias,
      :due_date,
      :created_by_user_id
    ])
    |> validate_required([:retro_session_id, :body])
    |> update_change(:body, &String.trim/1)
    |> validate_length(:body, min: 1, max: @max_body)
    |> validate_length(:assignee_alias, max: @max_assignee)
  end

  @doc false
  def update_changeset(action, attrs) do
    action
    |> cast(attrs, [:body, :assignee_alias, :due_date, :completed])
    |> update_change(:body, fn
      nil -> nil
      b -> String.trim(b)
    end)
    |> validate_length(:body, min: 1, max: @max_body)
    |> validate_length(:assignee_alias, max: @max_assignee)
  end
end
