defmodule Mixchamb.Chambers.ChamberVisit do
  @moduledoc """
  Per-user record of "this chamber was visited". One row per
  (user, chamber), upserted by `Chambers.touch_visit/2` on each
  ChamberLive mount. `last_visited_at` advances on every upsert,
  driving the recent-chambers list on the landing page.

  Lifetime is bounded by the FK cascade — when either the user
  (24-h idle reap) or the chamber (30-min idle reap) is deleted,
  the visit row goes with it.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "chamber_visits" do
    belongs_to :user, Mixchamb.Accounts.AnonymousUser
    belongs_to :chamber, Mixchamb.Chambers.Chamber
    field :last_visited_at, :utc_datetime
  end

  @doc false
  def changeset(visit, attrs) do
    visit
    |> cast(attrs, [:user_id, :chamber_id, :last_visited_at])
    |> validate_required([:user_id, :chamber_id, :last_visited_at])
    |> unique_constraint([:user_id, :chamber_id])
  end
end
