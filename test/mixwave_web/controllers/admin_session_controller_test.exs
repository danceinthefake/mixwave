defmodule MixwaveWeb.AdminSessionControllerTest do
  use MixwaveWeb.ConnCase, async: false

  describe "GET /admin/login" do
    test "renders the login form", %{conn: conn} do
      conn = get(conn, ~p"/admin/login")
      html = html_response(conn, 200)
      assert html =~ "Admin login"
      assert html =~ "name=\"session[username]\""
      assert html =~ "name=\"session[password]\""
    end

    test "redirects to /admin when already authenticated", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(admin_authenticated: true)
        |> get(~p"/admin/login")

      assert redirected_to(conn) == ~p"/admin"
    end
  end

  describe "POST /admin/login" do
    test "redirects to /admin and sets the session flag on valid env creds", %{conn: conn} do
      # config/test.exs sets admin_user="admin" admin_password="test"
      conn =
        post(conn, ~p"/admin/login", %{
          "session" => %{"username" => "admin", "password" => "test"}
        })

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, :admin_authenticated) == true
      assert get_session(conn, :admin_username) == "admin"
    end

    test "logs in with a DB-backed admin row and stashes the username", %{conn: conn} do
      {:ok, _} = Mixwave.Admins.create_admin(%{username: "kiki", password: "supersecret"})

      conn =
        post(conn, ~p"/admin/login", %{
          "session" => %{"username" => "kiki", "password" => "supersecret"}
        })

      assert redirected_to(conn) == ~p"/admin"
      assert get_session(conn, :admin_authenticated) == true
      assert get_session(conn, :admin_username) == "kiki"
    end

    test "re-renders the form with an error on bad creds", %{conn: conn} do
      conn =
        post(conn, ~p"/admin/login", %{
          "session" => %{"username" => "admin", "password" => "wrong"}
        })

      html = html_response(conn, 401)
      assert html =~ "Invalid username or password"
      refute get_session(conn, :admin_authenticated)
    end
  end

  describe "DELETE /admin/logout" do
    test "drops the admin flag and redirects home", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(admin_authenticated: true)
        |> delete(~p"/admin/logout")

      assert redirected_to(conn) == ~p"/"
      refute get_session(conn, :admin_authenticated)
    end
  end

  describe "the admin scope is gated" do
    test "GET /admin without auth redirects to /admin/login", %{conn: conn} do
      conn = get(conn, ~p"/admin")
      assert redirected_to(conn) =~ "/admin/login"
    end

    test "GET /admin with auth lands on the dashboard", %{conn: conn} do
      conn =
        conn
        |> Plug.Test.init_test_session(admin_authenticated: true)
        |> get(~p"/admin")

      assert html_response(conn, 200) =~ "Dashboard"
    end
  end
end
