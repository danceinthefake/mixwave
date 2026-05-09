defmodule MixwaveWeb.Plugs.AdminAuth do
  @moduledoc """
  HTTP Basic Auth gate for the `/admin/*` scope.

  Reads the username + password from runtime config (`:admin_user`,
  `:admin_password` under `:mixwave`); both default to compile-time
  test values so the dev server boots without env. In prod the
  release config sources them from `ADMIN_USER` / `ADMIN_PASSWORD`.

  No password set → the plug refuses every request, so a missing
  env in prod fails closed instead of opening the page wide.
  """
  import Plug.Conn

  @realm "mixwave-admin"

  def init(opts), do: opts

  def call(conn, _opts) do
    case credentials() do
      nil ->
        deny(conn, "Admin password not configured.")

      {user, pass} ->
        Plug.BasicAuth.basic_auth(conn, username: user, password: pass, realm: @realm)
    end
  end

  defp credentials do
    user = Application.get_env(:mixwave, :admin_user)
    pass = Application.get_env(:mixwave, :admin_password)

    if is_binary(user) and is_binary(pass) and pass != "" do
      {user, pass}
    end
  end

  defp deny(conn, reason) do
    conn
    |> put_resp_header("www-authenticate", "Basic realm=\"#{@realm}\"")
    |> send_resp(401, reason)
    |> halt()
  end
end
