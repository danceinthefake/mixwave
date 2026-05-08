defmodule Mixwave.Library.Song do
  @moduledoc """
  A song uploaded by an anonymous user. The audio file lives in
  Cloudflare R2 at `storage_key`; `waveform_peaks` is pre-extracted on
  upload (in the `Transcoder` worker) so the Vue waveform island can
  render without re-decoding the audio on every page load.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "songs" do
    field :title, :string
    field :description, :string
    field :genre, :string
    field :storage_key, :string
    field :duration_s, :float
    field :waveform_peaks, {:array, :float}, default: []

    belongs_to :user, Mixwave.Accounts.AnonymousUser
    has_many :comments, Mixwave.Library.Comment

    timestamps(type: :utc_datetime, updated_at: false)
  end

  @doc """
  Used by the create-song flow after the browser PUTs the file to R2
  and notifies us with the storage key.
  """
  def creation_changeset(song, attrs) do
    song
    |> cast(attrs, [
      :user_id,
      :title,
      :description,
      :genre,
      :storage_key,
      :duration_s,
      :waveform_peaks
    ])
    |> validate_required([:user_id, :title, :storage_key])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:description, max: 2_000)
    |> validate_length(:genre, max: 50)
    |> assoc_constraint(:user)
  end

  @doc """
  Used on the manage page when the owner edits title/description/genre.
  Storage_key and duration_s are not editable — those are owned by the
  upload flow.
  """
  def edit_changeset(song, attrs) do
    song
    |> cast(attrs, [:title, :description, :genre])
    |> validate_required([:title])
    |> validate_length(:title, min: 1, max: 200)
    |> validate_length(:description, max: 2_000)
    |> validate_length(:genre, max: 50)
  end
end
