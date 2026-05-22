defmodule Mixchamb.Chambers.Chamber do
  @moduledoc """
  A secret chamber — a link-only private chamber.

  Created by an `Mixchamb.Accounts.AnonymousUser`; identified by an
  unguessable `slug` that's also the URL segment users visit. The
  `activated_at` field flips from NULL to a timestamp the first
  time someone other than the creator joins; while it's NULL the
  chamber is in its 30-minute grace window and may be auto-deleted
  by `Mixchamb.Chambers.Server`.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  # Chamber kinds map 1:1 to presets in the Tone.js master FX bus
  # on the client (see `assets/vue/lib/audio.ts`). Add a new kind
  # here AND add a matching preset there, otherwise the client
  # falls back to whatever its last applied preset was. Music-only;
  # ignored when `activity != "music"`.
  @kinds ~w(vacuum anechoic room live hall cathedral plate spring echo)
  def kinds, do: @kinds

  # Activities a chamber can host. Each one lights up a different
  # Vue island in `Chamber.vue`. The default is `"music"` so existing
  # rows + new music chambers behave identically to v1-v3. Adding an
  # activity here is half the work; the other half is the matching
  # branch in `Chamber.vue` (see features/planning-poker.md for the
  # pattern).
  @activities ~w(music poker)
  def activities, do: @activities

  schema "chambers" do
    field :slug, :string
    field :activated_at, :utc_datetime
    field :title, :string
    field :last_activity_at, :utc_datetime
    field :kind, :string, default: "room"
    field :activity, :string, default: "music"
    # Creator-controlled REC toggle. When true, every broadcast
    # note is persisted to `chamber_events` for later replay.
    field :is_recording, :boolean, default: false

    belongs_to :creator, Mixchamb.Accounts.AnonymousUser, foreign_key: :creator_user_id

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc false
  def creation_changeset(chamber, attrs) do
    chamber
    |> cast(attrs, [:slug, :creator_user_id, :kind, :activity])
    |> validate_required([:slug, :creator_user_id])
    |> validate_inclusion(:kind, @kinds)
    |> validate_inclusion(:activity, @activities)
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

  @doc false
  def kind_changeset(chamber, attrs) do
    chamber
    |> cast(attrs, [:kind])
    |> validate_inclusion(:kind, @kinds)
  end

  @doc false
  def activity_changeset(chamber, attrs) do
    chamber
    |> cast(attrs, [:activity])
    |> validate_required([:activity])
    |> validate_inclusion(:activity, @activities)
  end

  @doc false
  def recording_changeset(chamber, attrs) do
    chamber
    |> cast(attrs, [:is_recording])
    |> validate_required([:is_recording])
  end

  @doc """
  Changeset for creating a system chamber — one that has no
  human creator (`creator_user_id` stays NULL). Used for
  singletons like the public Chaos Chamber. Bypasses the
  `creator_user_id` requirement that user-created chambers go
  through.
  """
  def system_changeset(chamber, attrs) do
    chamber
    |> cast(attrs, [:slug, :title, :kind])
    |> validate_required([:slug])
    |> validate_inclusion(:kind, @kinds)
    |> unique_constraint(:slug)
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
