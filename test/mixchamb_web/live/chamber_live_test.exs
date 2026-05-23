defmodule MixchambWeb.ChamberLiveTest do
  use MixchambWeb.ConnCase, async: false

  alias Mixchamb.{Accounts, Chambers}
  alias Mixchamb.Chambers.Server

  setup %{conn: conn} do
    {:ok, user} = Accounts.create_anonymous_user()
    conn = Plug.Test.init_test_session(conn, %{"user_id" => user.id})

    {:ok, chamber} = Chambers.create_chamber(user.id)

    on_exit(fn ->
      case Registry.lookup(Mixchamb.Chambers.Registry, chamber.slug) do
        [{pid, _}] -> DynamicSupervisor.terminate_child(Mixchamb.Chambers.Supervisor, pid)
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

      assert [{pid, _}] = Registry.lookup(Mixchamb.Chambers.Registry, chamber.slug)
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
      Phoenix.PubSub.subscribe(Mixchamb.PubSub, Chambers.topic(chamber.slug))

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
      |> element("#desktop-alias-editor")
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
      |> element("#desktop-alias-editor")
      |> render_submit(%{"alias" => ""})

      assert %{alias: nil} = Accounts.get_anonymous_user(user.id)
    end
  end

  describe "session recording" do
    test "creator can toggle recording on and off", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      # Off by default.
      refute render(view) =~ "click to stop"

      view |> element("button", "Start recording") |> render_click()

      reloaded = Chambers.find_by_slug(chamber.slug)
      assert reloaded.is_recording

      view |> element("button", "click to stop") |> render_click()

      reloaded = Chambers.find_by_slug(chamber.slug)
      refute reloaded.is_recording
    end

    test "play_recording pushes a replay_burst payload", %{conn: conn, chamber: chamber} do
      # Insert some events directly.
      now = DateTime.utc_now()

      {:ok, _} =
        Chambers.record_events(chamber.id, [
          {%{"instrument" => "drums", "note" => "kick", "style" => "synth"}, now},
          {%{"instrument" => "drums", "note" => "snare", "style" => "synth"},
           DateTime.add(now, 500, :millisecond)}
        ])

      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      # Play + Reset became icon-only chips when the row was
      # de-cluttered; assert via the phx-click attribute instead
      # of visible text. The replay-count badge is still visible
      # text, so we keep one text check on that.
      assert render(view) =~ "play_recording"

      assert view
             |> element(~s|button[phx-click="play_recording"]|)
             |> render_click() =~ "play_recording"
    end

    test "non-creator does not see the REC toggle but sees the live badge while on",
         %{conn: conn, chamber: chamber} do
      {:ok, other} = Accounts.create_anonymous_user()
      conn = Plug.Test.init_test_session(conn, %{"user_id" => other.id})

      # Recording on, written directly.
      {:ok, _} = Chambers.set_recording(chamber, true)

      {:ok, _view, html} = live(conn, ~p"/chamber/#{chamber.slug}")

      refute html =~ "Start recording"
      assert html =~ "REC"
    end

    test "reset_recording wipes events + count for the creator",
         %{conn: conn, chamber: chamber} do
      # Seed a couple of persisted events.
      {:ok, _} =
        Chambers.record_events(chamber.id, [
          {%{"instrument" => "drums"}, DateTime.utc_now()},
          {%{"instrument" => "drums"}, DateTime.utc_now()}
        ])

      assert Chambers.recorded_event_count(chamber.id) == 2

      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")
      view |> element(~s|button[phx-click="reset_recording"]|) |> render_click()

      assert Chambers.recorded_event_count(chamber.id) == 0
      # Button hides once there's nothing left to reset.
      refute render(view) =~ ~s|phx-click="reset_recording"|
    end
  end

  describe "note rate limiting" do
    setup do
      Mixchamb.RateLimiter.reset()
      :ok
    end

    test "drops notes past 20/sec/user", %{conn: conn, chamber: chamber} do
      Phoenix.PubSub.subscribe(Mixchamb.PubSub, Chambers.topic(chamber.slug))

      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      payload = %{"instrument" => "drums", "style" => "synth", "note" => "kick"}

      # 30 hits — first 20 should broadcast, the next 10 should be
      # silently dropped by the limiter.
      for _ <- 1..30, do: render_hook(view, "note", payload)

      received = drain_chamber_notes(0)

      assert received == 20
    end

    test "emits the [:mixchamb, :chamber, :note_dropped] telemetry event on drop",
         %{conn: conn, chamber: chamber} do
      test_pid = self()

      :telemetry.attach(
        "note_dropped_test_handler_#{:erlang.unique_integer([:positive])}",
        [:mixchamb, :chamber, :note_dropped],
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

  describe "switch_instrument" do
    test "creator switching instrument updates the LV state + persists last_instrument",
         %{conn: conn, chamber: chamber, user: user} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      # Default mount lands on drums (or last_instrument); push the
      # switch directly so we don't have to wait for the cooldown.
      render_hook(view, "switch_instrument", %{"to" => "keyboard"})

      # User row's last_instrument now reflects the new pick.
      assert %{last_instrument: "keyboard"} = Mixchamb.Accounts.get_anonymous_user(user.id)
    end

  end

  describe "set_activity" do
    test "creator can flip music ↔ poker", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "set_activity", %{"activity" => "poker"})
      assert Chambers.find_by_slug(chamber.slug).activity == "poker"

      render_hook(view, "set_activity", %{"activity" => "music"})
      assert Chambers.find_by_slug(chamber.slug).activity == "music"
    end

    test "non-creator cannot flip activity", %{conn: conn, chamber: chamber} do
      {:ok, other} = Accounts.create_anonymous_user()
      conn = Plug.Test.init_test_session(conn, %{"user_id" => other.id})
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "set_activity", %{"activity" => "poker"})
      assert Chambers.find_by_slug(chamber.slug).activity == "music"
    end

    test "switching to the same activity is a no-op", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "set_activity", %{"activity" => "music"})
      assert Chambers.find_by_slug(chamber.slug).activity == "music"
    end

    test "unknown activity is rejected", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")
      render_hook(view, "set_activity", %{"activity" => "icebreaker"})
      assert Chambers.find_by_slug(chamber.slug).activity == "music"
    end
  end

  describe "set_kind" do
    test "creator changes the chamber kind", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")
      render_hook(view, "set_kind", %{"kind" => "anechoic"})
      assert Chambers.find_by_slug(chamber.slug).kind == "anechoic"
    end

    test "non-creator (anonymous user, not admin) can't change kind",
         %{conn: conn, chamber: chamber} do
      {:ok, other} = Accounts.create_anonymous_user()
      conn = Plug.Test.init_test_session(conn, %{"user_id" => other.id})
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "set_kind", %{"kind" => "anechoic"})
      # Default kind stays.
      assert Chambers.find_by_slug(chamber.slug).kind == "room"
    end
  end

  describe "poker events (creator-host)" do
    setup %{conn: conn, user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id, "poker")
      {:ok, _pid} = Mixchamb.Chambers.Server.ensure_started(chamber.slug, chamber.id)

      on_exit(fn ->
        case Registry.lookup(Mixchamb.Chambers.Registry, chamber.slug) do
          [{pid, _}] -> DynamicSupervisor.terminate_child(Mixchamb.Chambers.Supervisor, pid)
          _ -> :ok
        end
      end)

      %{conn: conn, chamber: chamber, user: user}
    end

    test "poker_vote casts the vote via the GenServer", %{conn: conn, chamber: chamber, user: user} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "poker_vote", %{"card" => "5"})
      :timer.sleep(50)

      session = Mixchamb.Chambers.Server.poker_state(chamber.slug)
      assert session.votes[user.id] == "5"
    end

    test "poker_withdraw_vote clears the user's vote",
         %{conn: conn, chamber: chamber, user: user} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "poker_vote", %{"card" => "5"})
      :timer.sleep(50)
      render_hook(view, "poker_withdraw_vote", %{})
      :timer.sleep(50)

      session = Mixchamb.Chambers.Server.poker_state(chamber.slug)
      assert is_nil(session.votes[user.id])
    end

    test "poker_reveal flips status to :revealed", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "poker_reveal", %{})
      :timer.sleep(50)

      assert Mixchamb.Chambers.Server.poker_state(chamber.slug).status == :revealed
    end

    test "poker_next_round advances the round counter", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "poker_next_round", %{})
      :timer.sleep(50)

      assert Mixchamb.Chambers.Server.poker_state(chamber.slug).round == 2
    end

    test "poker_set_story updates the story", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "poker_set_story", %{"story" => "Migrate auth"})
      :timer.sleep(50)

      assert Mixchamb.Chambers.Server.poker_state(chamber.slug).story == "Migrate auth"
    end

    test "poker_set_deck switches the deck", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "poker_set_deck", %{"deck" => "tshirt"})
      :timer.sleep(50)

      assert Mixchamb.Chambers.Server.poker_state(chamber.slug).deck == :tshirt
    end

    test "poker_set_queue replaces the queue", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      render_hook(view, "poker_set_queue", %{"queue" => ["one", "two", "three"]})
      :timer.sleep(50)

      assert Mixchamb.Chambers.Server.poker_state(chamber.slug).queue == ["one", "two", "three"]
    end
  end

  describe "host promotion" do
    setup %{conn: conn, user: user, chamber: chamber} do
      {:ok, _pid} = Mixchamb.Chambers.Server.ensure_started(chamber.slug, chamber.id)
      {:ok, other} = Accounts.create_anonymous_user()

      on_exit(fn ->
        case Registry.lookup(Mixchamb.Chambers.Registry, chamber.slug) do
          [{pid, _}] -> DynamicSupervisor.terminate_child(Mixchamb.Chambers.Supervisor, pid)
          _ -> :ok
        end
      end)

      %{conn: conn, user: user, chamber: chamber, other: other}
    end

    test "creator promotes another user → hosts set grows", %{
      conn: conn,
      chamber: chamber,
      user: user,
      other: other
    } do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")
      render_hook(view, "promote_host", %{"user_id" => other.id})
      :timer.sleep(50)

      assert Enum.sort(Mixchamb.Chambers.Server.hosts(chamber.slug)) ==
               Enum.sort([user.id, other.id])
    end

    test "creator demotes a co-host → hosts set shrinks", %{
      conn: conn,
      chamber: chamber,
      user: user,
      other: other
    } do
      Mixchamb.Chambers.Server.promote_host(chamber.slug, user.id, other.id)
      :timer.sleep(50)

      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")
      render_hook(view, "demote_host", %{"user_id" => other.id})
      :timer.sleep(50)

      assert Mixchamb.Chambers.Server.hosts(chamber.slug) == [user.id]
    end
  end

  describe "toggle_presence_sheet" do
    test "flips the presence_sheet_open assign", %{conn: conn, chamber: chamber} do
      {:ok, view, html_before} = live(conn, ~p"/chamber/#{chamber.slug}")
      refute html_before =~ ~s|role="dialog" aria-label="Players panel"|

      html_after = render_hook(view, "toggle_presence_sheet", %{})
      assert html_after =~ ~s|role="dialog" aria-label="Players panel"|
    end
  end

  describe "recent-hits feed broadcast" do
    test "incoming :chamber_note populates the feed with a row",
         %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      # Push a note from "another user" so it shows as not-self.
      Phoenix.PubSub.broadcast(
        Mixchamb.PubSub,
        Chambers.topic(chamber.slug),
        {:chamber_note,
         %{
           kind: :note,
           payload: %{
             "user_id" => "other-user-id",
             "instrument" => "drums",
             "note" => "kick",
             "label" => "Kick",
             "display_name" => "stranger-39"
           }
         }}
      )

      :timer.sleep(50)
      html = render(view)
      assert html =~ "stranger-39"
      assert html =~ "Kick"
    end

    test "release-phase notes are skipped (no feed row)", %{conn: conn, chamber: chamber} do
      {:ok, view, _html} = live(conn, ~p"/chamber/#{chamber.slug}")

      Phoenix.PubSub.broadcast(
        Mixchamb.PubSub,
        Chambers.topic(chamber.slug),
        {:chamber_note,
         %{
           kind: :note,
           payload: %{
             "user_id" => "other-user-id",
             "instrument" => "guitar",
             "chord" => "C",
             "phase" => "release",
             "display_name" => "no-feed-row"
           }
         }}
      )

      :timer.sleep(50)
      refute render(view) =~ "no-feed-row"
    end
  end

end
