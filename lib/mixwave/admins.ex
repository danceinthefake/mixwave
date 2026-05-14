defmodule Mixwave.Admins do
  @moduledoc """
  Per-user admin accounts (the `/admin` section). Logging in with
  one of these rows attributes audit entries to the row's
  username instead of the catch-all "admin" env user — see
  `MixwaveWeb.AdminSessionController` for the env break-glass
  fallback when every row's password has been forgotten.
  """

  import Ecto.Query

  alias Mixwave.Admins.Admin
  alias Mixwave.Repo

  @doc """
  Creates an admin row. `attrs` must include `username` and
  `password`; the password is hashed via bcrypt.
  """
  def create_admin(attrs) do
    %Admin{}
    |> Admin.registration_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Authenticates `username` + `password` against the admins table.
  Returns the `Admin` struct on success (and bumps `last_login_at`),
  `nil` otherwise. Constant-time on miss to avoid leaking which
  usernames exist.
  """
  def authenticate(username, password) when is_binary(username) and is_binary(password) do
    case get_by_username(username) do
      nil ->
        # Run a dummy verify so the timing of "no such user" looks
        # like "wrong password". `no_user_verify/0` is bcrypt_elixir's
        # canonical way to do this.
        Bcrypt.no_user_verify()
        nil

      admin ->
        if Bcrypt.verify_pass(password, admin.password_hash) do
          {:ok, updated} = admin |> Admin.login_changeset() |> Repo.update()
          updated
        else
          nil
        end
    end
  end

  @doc """
  Looks up an admin by username. nil if none.
  """
  def get_by_username(username) when is_binary(username) do
    Repo.get_by(Admin, username: username)
  end

  @doc """
  Looks up an admin by id. nil if none.
  """
  def get_admin(id) when is_binary(id), do: Repo.get(Admin, id)

  @doc """
  All admins, newest first. Used by the Ops tab's admin list.
  """
  def list_admins do
    Admin
    |> order_by([a], desc: a.inserted_at)
    |> Repo.all()
  end

  @doc "Count of admins in the table."
  def count_admins, do: Repo.aggregate(Admin, :count, :id)

  @doc """
  Deletes an admin row.
  """
  def delete_admin(%Admin{} = admin), do: Repo.delete(admin)

  def delete_admin(id) when is_binary(id) do
    case get_admin(id) do
      nil -> {:error, :not_found}
      admin -> delete_admin(admin)
    end
  end

  @doc """
  Changes an existing admin's password.
  """
  def change_password(%Admin{} = admin, new_password) do
    admin
    |> Admin.password_changeset(%{password: new_password})
    |> Repo.update()
  end
end
