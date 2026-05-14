defmodule MixwaveWeb.AdminSessionController do
  @moduledoc """
  Login + logout for the `/admin` section.

  Authentication tries two sources, in order:

    1. **Database** — `Mixwave.Admins.authenticate/2`. Per-user
       rows with bcrypt-hashed passwords. The audit log
       attributes actions to the row's username.
    2. **Env fallback** — `:admin_user` / `:admin_password` from
       app env. Intended as a break-glass route: if every admin
       has forgotten their password, the env credentials still
       let an operator in. Audit rows from an env login attribute
       to the env username (typically "admin").

  Both paths set the same session keys
  (`:admin_authenticated`, `:admin_username`), so downstream
  plugs and LVs can stay source-agnostic.
  """
  use MixwaveWeb, :controller

  alias Mixwave.Admins

  @doc """
  Renders the login form. If the user is already authenticated,
  short-circuits to the dashboard so a stale `/admin/login` URL
  doesn't show the form needlessly.
  """
  def new(conn, _params) do
    if get_session(conn, :admin_authenticated) do
      redirect(conn, to: ~p"/admin")
    else
      render(conn, :new, error: nil, username: "")
    end
  end

  @doc """
  Validates submitted credentials, first against the admins
  table, then against the env fallback. On success: regenerates
  the session id, stashes the authenticated flag + username,
  redirects to `/admin`. On failure: re-renders the form with an
  error message and the entered username preserved.
  """
  def create(conn, %{"session" => %{"username" => user, "password" => pass}}) do
    case verify(user, pass) do
      {:ok, username} ->
        conn
        |> configure_session(renew: true)
        |> put_session(:admin_authenticated, true)
        |> put_session(:admin_username, username)
        |> put_flash(:info, "Welcome, #{username}.")
        |> redirect(to: ~p"/admin")

      :error ->
        conn
        |> put_status(:unauthorized)
        |> render(:new, error: "Invalid username or password.", username: user)
    end
  end

  @doc """
  Drops the admin session flag and bounces home. Doesn't tear
  down the rest of the session (the anonymous user stays signed
  in for the regular app).
  """
  def delete(conn, _params) do
    conn
    |> delete_session(:admin_authenticated)
    |> delete_session(:admin_username)
    |> put_flash(:info, "Logged out.")
    |> redirect(to: ~p"/")
  end

  # First try the admins table. If that doesn't match, try the env
  # break-glass credentials. Returns {:ok, username} or :error.
  defp verify(user, pass) when is_binary(user) and is_binary(pass) do
    case Admins.authenticate(user, pass) do
      %Mixwave.Admins.Admin{username: username} ->
        {:ok, username}

      nil ->
        if env_match?(user, pass) do
          {:ok, Application.get_env(:mixwave, :admin_user, "admin")}
        else
          :error
        end
    end
  end

  defp env_match?(user, pass) do
    expected_user = Application.get_env(:mixwave, :admin_user)
    expected_pass = Application.get_env(:mixwave, :admin_password)

    is_binary(expected_user) and is_binary(expected_pass) and expected_pass != "" and
      Plug.Crypto.secure_compare(user, expected_user) and
      Plug.Crypto.secure_compare(pass, expected_pass)
  end
end
