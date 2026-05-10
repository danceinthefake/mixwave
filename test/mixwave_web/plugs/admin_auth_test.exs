defmodule MixwaveWeb.Plugs.AdminAuthTest do
  use MixwaveWeb.ConnCase, async: false

  alias MixwaveWeb.Plugs.AdminAuth

  setup %{conn: conn} do
    conn =
      conn
      |> Plug.Test.init_test_session(%{})
      |> Phoenix.Controller.fetch_flash()

    %{conn: conn}
  end

  describe "with admin password configured" do
    test "passes through when :admin_authenticated is set in the session", %{conn: conn} do
      conn = put_session(conn, :admin_authenticated, true)
      conn = AdminAuth.call(conn, [])
      refute conn.halted
    end

    test "redirects to /admin/login when the session flag is missing", %{conn: conn} do
      conn = AdminAuth.call(conn, [])
      assert conn.halted
      assert redirected_to(conn) == "/admin/login"
    end
  end

  describe "fails closed when no admin password is configured" do
    setup do
      original = Application.get_env(:mixwave, :admin_password)

      on_exit(fn ->
        Application.put_env(:mixwave, :admin_password, original)
      end)

      Application.put_env(:mixwave, :admin_password, nil)
      :ok
    end

    test "returns 503 even with the session flag set", %{conn: conn} do
      conn =
        conn
        |> put_session(:admin_authenticated, true)
        |> AdminAuth.call([])

      assert conn.halted
      assert conn.status == 503
    end
  end
end
