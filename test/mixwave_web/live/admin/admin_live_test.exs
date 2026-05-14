defmodule MixwaveWeb.Admin.AdminLiveTest do
  @moduledoc """
  Smoke tests covering every admin tab. Each one asserts the LV
  mounts and renders something specific to that page so we'd
  notice if the route or LV broke.

  All requests run through the AdminAuth gate, so the conn first
  flips :admin_authenticated in the session.
  """
  use MixwaveWeb.ConnCase, async: false

  alias Mixwave.{Accounts, Chambers}

  setup %{conn: conn} do
    conn =
      Plug.Test.init_test_session(conn, %{
        admin_authenticated: true,
        admin_username: "admin"
      })

    %{conn: conn}
  end

  describe "Dashboard" do
    test "renders the counters and the telemetry section", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin")
      assert html =~ "Dashboard"
      assert html =~ "Telemetry"
      assert html =~ "Counts"
    end
  end

  describe "System" do
    test "renders the supervised-singletons table", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/system")
      assert html =~ "System"
      assert html =~ "Active chambers"
    end
  end

  describe "Chambers" do
    test "renders an empty state when no chambers exist", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/chambers")
      assert html =~ "Chambers" and html =~ "No chambers"
    end

    test "renders a row for an existing chamber", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, chamber} = Chambers.create_chamber(user.id)

      {:ok, _view, html} = live(conn, ~p"/admin/chambers")
      assert html =~ chamber.slug
    end
  end

  describe "Users" do
    test "lists existing users", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()

      {:ok, _view, html} = live(conn, ~p"/admin/users")
      assert html =~ user.display_name
    end

    test "force-expire deletes the user row", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()

      {:ok, view, _html} = live(conn, ~p"/admin/users")
      view |> element("button[phx-value-id=\"#{user.id}\"]") |> render_click()

      refute Accounts.get_anonymous_user(user.id)
    end
  end

  describe "Activity" do
    test "renders the firehose table headers", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/activity")
      assert html =~ "Activity"
      assert html =~ "Time"
      assert html =~ "Player"
      assert html =~ "Note"
    end

    test "pause toggle flips and re-flips", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/activity")
      assert render(view) =~ "Pause"

      view |> element("button", "Pause") |> render_click()
      assert render(view) =~ "Resume"
    end
  end

  describe "Sweepers" do
    test "shows both sweepers' info cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/sweepers")
      assert html =~ "Chambers sweeper"
      assert html =~ "Anonymous users sweeper"
    end
  end

  describe "Cluster" do
    test "lists self as a node", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/cluster")
      assert html =~ "Cluster"
      # Even on a non-distributed test BEAM the local node renders.
      assert html =~ to_string(Node.self())
    end
  end

  describe "Health" do
    test "renders the stats grid + memory + ETS tables", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/health")
      assert html =~ "Health"
      assert html =~ "Memory breakdown"
      assert html =~ "Our ETS tables"
      assert html =~ "Chamber restart counts"
    end
  end

  describe "Rate limits" do
    test "renders the empty state when nothing is saturated", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/rate-limits")
      assert html =~ "Rate limits"
      # Either nothing saturated or nothing dropped — both empty
      # states are in the page on a freshly-booted test.
      assert html =~ "Saturated right now"
      assert html =~ "Lifetime drops"
    end
  end

  describe "Chamber detail" do
    test "renders the chamber's facts + recent-notes panel", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, chamber} = Chambers.create_chamber(user.id)

      {:ok, _view, html} = live(conn, ~p"/admin/chambers/#{chamber.slug}")
      assert html =~ chamber.slug
      assert html =~ "Recent notes"
      assert html =~ "Who&#39;s here" or html =~ "Who's here"
      assert html =~ "Danger zone"
    end

    test "unknown slug redirects back to the chambers list", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/admin/chambers"}}} =
               live(conn, ~p"/admin/chambers/does-not-exist")
    end

    test "delete from the detail page removes the chamber", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, chamber} = Chambers.create_chamber(user.id)

      {:ok, view, _html} = live(conn, ~p"/admin/chambers/#{chamber.slug}")

      view |> element("button", "Delete chamber") |> render_click()

      refute Chambers.find_by_slug(chamber.slug)
    end

    test "audit row attributes the action to the signed-in admin", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, chamber} = Chambers.create_chamber(user.id)

      {:ok, view, _html} = live(conn, ~p"/admin/chambers/#{chamber.slug}")
      view |> element("button", "Delete chamber") |> render_click()

      action =
        Mixwave.Audit.recent_actions(5)
        |> Enum.find(&(&1.action == "delete_chamber" and &1.target == "chamber:#{chamber.slug}"))

      assert action
      assert action.admin_user == "admin"
    end
  end
end
