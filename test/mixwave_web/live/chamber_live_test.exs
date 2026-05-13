defmodule MixwaveWeb.ChamberLiveTest do
  use MixwaveWeb.ConnCase, async: false

  alias Mixwave.{Accounts, Chambers}
  alias Mixwave.Chambers.Server

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_anonymous_user()
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})

    {:ok, chamber} = Chambers.create_chamber(user.id)

    on_exit(fn ->
      case Registry.lookup(Mixwave.Chambers.Registry, chamber.slug) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(Mixwave.Chambers.Supervisor, pid)
        _ -> :ok
      end
    end)

    %{conn: conn, user: user, chamber: chamber}
  end

  describe "mount" do
    test "renders the chamber and its title", %{conn: conn, chamber: chamber} do
      {:ok, _view, html} = live(conn, ~p"/chamber/#{chamber.slug}")
      assert html =~ chamber.slug or html =~ "Chamber"
    end

    test "starts the per-chamber GenServer", %{conn: conn, chamber: chamber} do
      {:ok, _view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      assert [{pid, _}] = Registry.lookup(Mixwave.Chambers.Registry, chamber.slug)
      assert Process.alive?(pid)
    end

    test "redirects to / when the slug doesn't exist", %{conn: conn} do
      assert {:error, {:live_redirect, %{to: "/"}}} =
               live(conn, ~p"/chamber/does-not-exist")
    end
  end

  describe "creator-only invite banner" do
    test "shows for the creator while the chamber is in grace", %{conn: conn, chamber: chamber} do
      {:ok, _view, html} = live(conn, ~p"/chamber/#{chamber.slug}")
      assert html =~ "Share this chamber"
    end

    test "hides for non-creators", %{conn: conn, chamber: chamber} do
      {:ok, other} = Accounts.create_anonymous_user()
      conn = Plug.Test.init_test_session(conn, %{"user_id" => other.id})

      {:ok, _view, html} = live(conn, ~p"/chamber/#{chamber.slug}")
      refute html =~ "Share this chamber"
    end
  end

  describe "note event roundtrip" do
    test "pushing a note records it in the GenServer + broadcasts on the chamber topic",
         %{conn: conn, chamber: chamber} do
      Phoenix.PubSub.subscribe(Mixwave.PubSub, Chambers.topic(chamber.slug))

      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      payload = %{"instrument" => "drums", "style" => "synth", "note" => "kick"}
      render_hook(view, "note", payload)

      assert_receive {:chamber_note, %{kind: :note, payload: received}}, 500
      assert received["instrument"] == "drums"
      assert received["display_name"]

      info = Server.info(chamber.slug)
      assert info.event_count >= 1
    end
  end

  describe "alias" do
    test "set_alias updates the DB + presence meta + UI", %{
      conn: conn,
      chamber: chamber,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      # Submit the alias form.
      view
      |> element("#alias-editor")
      |> render_submit(%{"alias" => "Bob"})

      # DB row updated.
      assert %{alias: "Bob"} = Accounts.get_anonymous_user(user.id)

      # Sidebar primary line now shows the alias with the anon
      # name under it.
      html = render(view)
      assert html =~ "Bob"
      assert html =~ user.display_name
    end

    test "submitting a blank alias clears it", %{conn: conn, chamber: chamber, user: user} do
      {:ok, _} = Accounts.set_alias(user, "Bob")

      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      view
      |> element("#alias-editor")
      |> render_submit(%{"alias" => ""})

      assert %{alias: nil} = Accounts.get_anonymous_user(user.id)
    end
  end

  describe "note rate limiting" do
    setup do
      Mixwave.RateLimiter.reset()
      :ok
    end

    test "drops notes past 20/sec/user", %{conn: conn, chamber: chamber} do
      Phoenix.PubSub.subscribe(Mixwave.PubSub, Chambers.topic(chamber.slug))

      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      payload = %{"instrument" => "drums", "style" => "synth", "note" => "kick"}

      # 30 hits — first 20 should broadcast, the next 10 should be
      # silently dropped by the limiter.
      for _ <- 1..30, do: render_hook(view, "note", payload)

      received = drain_chamber_notes(0)

      assert received == 20
    end

    test "emits the [:mixwave, :chamber, :note_dropped] telemetry event on drop",
         %{conn: conn, chamber: chamber} do
      test_pid = self()

      :telemetry.attach(
        "note_dropped_test_handler_#{:erlang.unique_integer([:positive])}",
        [:mixwave, :chamber, :note_dropped],
        fn _, _, _, _ -> send(test_pid, :dropped) end,
        nil
      )

      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")
      payload = %{"instrument" => "drums", "style" => "synth", "note" => "kick"}

      for _ <- 1..25, do: render_hook(view, "note", payload)

      assert_receive :dropped, 500
    end
  end

  # Counts {:chamber_note, _} messages already buffered on the test
  # PID's mailbox. Stops as soon as none arrive within 50 ms.
  defp drain_chamber_notes(acc) do
    receive do
      {:chamber_note, _} -> drain_chamber_notes(acc + 1)
    after
      50 -> acc
    end
  end
end
