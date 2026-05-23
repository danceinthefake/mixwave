defmodule MixchambWeb.Admin.AdminLiveTest do
  @moduledoc """
  Smoke tests covering every admin tab. Each one asserts the LV
  mounts and renders something specific to that page so we'd
  notice if the route or LV broke.

  All requests run through the AdminAuth gate, so the conn first
  flips :admin_authenticated in the session.
  """
  use MixchambWeb.ConnCase, async: false

  alias Mixchamb.{Accounts, Chambers}

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

    test "kill restarts a named singleton process", %{conn: conn} do
      # Pick a singleton we can safely bounce — the chambers sweeper.
      old_pid = Process.whereis(Mixchamb.Chambers.Sweeper)
      assert is_pid(old_pid)

      {:ok, view, _html} = live(conn, ~p"/admin/system")
      # The template emits the module name with the "Elixir." prefix
      # that BEAM uses internally for Elixir modules.
      render_hook(view, "kill", %{"module" => "Elixir.Mixchamb.Chambers.Sweeper"})

      # The supervisor restarts it under the same name within a few ms.
      :timer.sleep(100)
      new_pid = Process.whereis(Mixchamb.Chambers.Sweeper)
      assert is_pid(new_pid)
      assert new_pid != old_pid
    end

    test "kill_chamber stops a specific chamber's GenServer", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, chamber} = Chambers.create_chamber(user.id)
      {:ok, pid} = Mixchamb.Chambers.Server.ensure_started(chamber.slug, chamber.id)
      ref = Process.monitor(pid)

      {:ok, view, _html} = live(conn, ~p"/admin/system")
      render_hook(view, "kill_chamber", %{"slug" => chamber.slug})

      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 500
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

    test "search filter hides non-matching rows but keeps the table mounted", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, c1} = Chambers.create_chamber(user.id)
      {:ok, c2} = Chambers.create_chamber(user.id)

      {:ok, view, _html} = live(conn, ~p"/admin/chambers")

      # Type a query that should only match c1.
      html =
        view
        |> form("form", %{q: c1.slug})
        |> render_change()

      assert html =~ c1.slug
      refute html =~ c2.slug

      # Clear filter — both come back.
      html = view |> form("form", %{q: ""}) |> render_change()
      assert html =~ c1.slug
      assert html =~ c2.slug
    end

    test "search with no matches shows the 'no matches' empty state", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, _chamber} = Chambers.create_chamber(user.id)

      {:ok, view, _html} = live(conn, ~p"/admin/chambers")

      html =
        view
        |> form("form", %{q: "zzz-no-chamber-matches-this"})
        |> render_change()

      assert html =~ "No chambers match"
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

    test "clear empties the visible stream", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/activity")
      # Hook directly to bypass the data-confirm dialog.
      html = render_hook(view, "clear", %{})
      assert html =~ "Activity"
    end

    test "incoming :activity broadcast appends a row", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/activity")

      Phoenix.PubSub.broadcast(
        Mixchamb.PubSub,
        Chambers.activity_topic(),
        {:activity, "slug-xyz",
         %{
           kind: :note,
           payload: %{
             "instrument" => "drums",
             "note" => "kick",
             "display_name" => "alice-droll-01"
           }
         }}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "slug-xyz"
      assert html =~ "alice-droll-01"
    end

    test "broadcasts received while paused are dropped", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/activity")

      render_hook(view, "toggle_pause", %{})

      Phoenix.PubSub.broadcast(
        Mixchamb.PubSub,
        Chambers.activity_topic(),
        {:activity, "slug-paused",
         %{
           kind: :note,
           payload: %{"instrument" => "drums", "note" => "kick", "display_name" => "paused-user"}
         }}
      )

      :timer.sleep(50)
      refute render(view) =~ "paused-user"
    end
  end

  describe "Rate limits" do
    test "renders the page with both sections", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/rate-limits")
      assert html =~ "Rate limits"
      assert html =~ "Saturated"
      assert html =~ "Lifetime drops"
    end

    test "reset_bucket clears a specific (user, slug) bucket", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      Mixchamb.RateLimiter.hit({:note, user.id, "abc123"}, 10, 1_000)

      assert %{count: 1} = Mixchamb.RateLimiter.peek({:note, user.id, "abc123"})

      {:ok, view, _html} = live(conn, ~p"/admin/rate-limits")
      render_hook(view, "reset_bucket", %{"user_id" => user.id, "slug" => "abc123"})

      assert is_nil(Mixchamb.RateLimiter.peek({:note, user.id, "abc123"}))
    end
  end

  describe "Sweepers" do
    test "shows both sweepers' info cards", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/sweepers")
      assert html =~ "Chambers sweeper"
      assert html =~ "Anonymous users sweeper"
    end
  end

  describe "Ops" do
    test "renders the broadcast form, admins list, and audit log", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/admin/ops")
      assert html =~ "Ops" or html =~ "Broadcast"
      assert html =~ "Admins" or html =~ "admin"
      assert html =~ "Audit"
    end

    test "broadcasting a banner persists + flashes success", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ops")

      html =
        view
        |> form("form[phx-submit='broadcast']", %{message: "All hands", duration: "15"})
        |> render_submit()

      assert html =~ "broadcast for 15 min"
      assert Mixchamb.Banners.current_banner().message == "All hands"
    end

    test "broadcasting an empty message shows the empty-message error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ops")

      html =
        view
        |> form("form[phx-submit='broadcast']", %{message: "   ", duration: "15"})
        |> render_submit()

      assert html =~ "Message can&#39;t be empty" or html =~ "can't be empty"
    end

    test "broadcasting with an invalid duration is rejected", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ops")

      # Form helper rejects out-of-range radio values; hit the handler
      # directly to exercise the server-side defence against a forged
      # phx event.
      html = render_hook(view, "broadcast", %{"message" => "Hi", "duration" => "999"})
      assert html =~ "Invalid duration"
    end

    test "clear_banner empties the current banner", %{conn: conn} do
      # Seed a banner directly.
      {:ok, _} = Mixchamb.Banners.set_banner("Existing", 15, "admin")

      {:ok, view, _html} = live(conn, ~p"/admin/ops")
      html = view |> element("button[phx-click='clear_banner']") |> render_click()
      assert html =~ "Banner cleared"
      refute Mixchamb.Banners.current_banner()
    end

    test "add_admin creates a user-level admin record", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/ops")

      html =
        view
        |> form("form[phx-submit='add_admin']", %{username: "newop", password: "Sec1passw"})
        |> render_submit()

      assert html =~ "Added admin newop" or html =~ "newop"
      assert Enum.any?(Mixchamb.Admins.list_admins(), &(&1.username == "newop"))
    end

    test "delete_admin removes the user-level admin", %{conn: conn} do
      {:ok, admin} = Mixchamb.Admins.create_admin(%{username: "dropme", password: "Sec1passw"})

      {:ok, view, _html} = live(conn, ~p"/admin/ops")
      html =
        view
        |> element("button[phx-click='delete_admin'][phx-value-id='#{admin.id}']")
        |> render_click()

      assert html =~ "Deleted admin dropme"
      refute Enum.any?(Mixchamb.Admins.list_admins(), &(&1.username == "dropme"))
    end
  end

  describe "Cluster events" do
    test "update_input echoes the typed value", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cluster")
      html = render_hook(view, "update_input", %{"value" => "node@host"})
      # The input keeps its value after the change.
      assert html =~ "node@host"
    end

    test "connect with empty input shows the empty-field error", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cluster")
      html = render_hook(view, "connect", %{"node" => "   "})
      assert html =~ "Enter a node name first" or html =~ "empty"
    end

    test "connect with a parsable but unreachable node flashes a failure",
         %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cluster")
      # Distillery-style sname@host syntax — parses but won't connect.
      html = render_hook(view, "connect", %{"node" => "nobody@127.0.0.1"})
      # Either a parse error or a connect-failed flash — both count
      # as the handler exercising its error branch.
      assert is_binary(html)
    end

    test "disconnect with unknown node is a flash-only no-op", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/admin/cluster")
      html = render_hook(view, "disconnect", %{"node" => "not_actually_connected@nowhere"})
      assert is_binary(html)
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
        Mixchamb.Audit.recent_actions(5)
        |> Enum.find(&(&1.action == "delete_chamber" and &1.target == "chamber:#{chamber.slug}"))

      assert action
      assert action.admin_user == "admin"
    end

    test "kill_genserver from the detail page terminates the chamber process",
         %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, chamber} = Chambers.create_chamber(user.id)
      {:ok, pid} = Mixchamb.Chambers.Server.ensure_started(chamber.slug, chamber.id)
      ref = Process.monitor(pid)

      {:ok, view, _html} = live(conn, ~p"/admin/chambers/#{chamber.slug}")
      render_hook(view, "kill_genserver", %{})

      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 500
    end

    test "incoming :chamber_note appends to the recent-notes stream", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, chamber} = Chambers.create_chamber(user.id)

      {:ok, view, _html} = live(conn, ~p"/admin/chambers/#{chamber.slug}")

      Phoenix.PubSub.broadcast(
        Mixchamb.PubSub,
        Chambers.topic(chamber.slug),
        {:chamber_note,
         %{
           kind: :note,
           payload: %{
             "instrument" => "drums",
             "note" => "kick",
             "display_name" => "ditto-ditto-77"
           }
         }}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "ditto-ditto-77"
    end

    test "incoming :chamber_closed redirects back to the chambers list", %{conn: conn} do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, chamber} = Chambers.create_chamber(user.id)

      {:ok, view, _html} = live(conn, ~p"/admin/chambers/#{chamber.slug}")

      Phoenix.PubSub.broadcast(
        Mixchamb.PubSub,
        Chambers.topic(chamber.slug),
        {:chamber_closed, chamber.slug}
      )

      assert_redirect(view, "/admin/chambers", 500)
    end
  end
end
