defmodule Mixwave.Admins.Admin do
  @moduledoc """
  A privileged admin user. Stores a bcrypt-hashed password and
  the last-login timestamp; everything else (audit, sessions)
  hangs off the username.

  Usernames are stored in a `citext` column so login is
  case-insensitive without forcing the caller to lowercase.
  """
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}

  schema "admins" do
    field :username, :string
    field :password, :string, virtual: true, redact: true
    field :password_hash, :string, redact: true
    field :last_login_at, :utc_datetime_usec

    timestamps(type: :utc_datetime)
  end

  @doc """
  Changeset for creating a new admin row. Hashes the password
  on the way in.
  """
  def registration_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:username, :password])
    |> validate_required([:username, :password])
    |> validate_length(:username, min: 2, max: 32)
    |> validate_format(:username, ~r/^[a-z0-9._-]+$/i,
      message: "must be letters, numbers, dot, dash, or underscore"
    )
    |> validate_length(:password, min: 8, max: 72)
    |> unsafe_validate_unique(:username, Mixwave.Repo)
    |> unique_constraint(:username)
    |> put_password_hash()
  end

  @doc """
  Changeset for changing the password on an existing row.
  """
  def password_changeset(admin, attrs) do
    admin
    |> cast(attrs, [:password])
    |> validate_required([:password])
    |> validate_length(:password, min: 8, max: 72)
    |> put_password_hash()
  end

  @doc """
  Stamps `last_login_at` to now.
  """
  def login_changeset(admin) do
    change(admin, last_login_at: DateTime.utc_now())
  end

  defp put_password_hash(%Ecto.Changeset{valid?: true, changes: %{password: pass}} = changeset) do
    changeset
    |> put_change(:password_hash, Bcrypt.hash_pwd_salt(pass))
    |> delete_change(:password)
  end

  defp put_password_hash(changeset), do: changeset
end
