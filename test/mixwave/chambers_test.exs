defmodule Mixwave.ChambersTest do
  use Mixwave.DataCase, async: false

  alias Mixwave.{Accounts, Chambers}
  alias Mixwave.Chambers.{Chamber, Server}

  setup do
    {:ok, user} = Accounts.create_anonymous_user()
    %{user: user}
  end

  describe "create_chamber/1" do
    test "inserts a row with a generated slug + creator", %{user: user} do
      assert {:ok, %Chamber{} = chamber} = Chambers.create_chamber(user.id)
      assert chamber.creator_user_id == user.id
      assert chamber.slug =~ ~r/^[A-Za-z0-9_-]+$/
      # A fresh chamber has nil activation; the grace window applies.
      assert is_nil(chamber.activated_at)
    end

    test "two calls produce different slugs", %{user: user} do
      {:ok, a} = Chambers.create_chamber(user.id)
      {:ok, b} = Chambers.create_chamber(user.id)
      refute a.slug == b.slug
    end
  end

  describe "find_by_slug/1 + find_by_id/1" do
    test "returns the chamber for both lookups", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)
      assert Chambers.find_by_slug(chamber.slug).id == chamber.id
      assert Chambers.find_by_id(chamber.id).slug == chamber.slug
    end

    test "returns nil when missing" do
      assert is_nil(Chambers.find_by_slug("does-not-exist"))
      assert is_nil(Chambers.find_by_id(Ecto.UUID.generate()))
    end
  end

  describe "ensure_chaos_chamber/0" do
    test "creates the singleton on first call and returns it on subsequent ones" do
      assert {:ok, %Chamber{} = chaos} = Chambers.ensure_chaos_chamber()
      assert chaos.slug == Chambers.chaos_slug()
      assert is_nil(chaos.creator_user_id)

      # Second call returns the same row, doesn't create a new one.
      assert {:ok, %Chamber{id: id}} = Chambers.ensure_chaos_chamber()
      assert id == chaos.id
      assert Chambers.count_chambers() == 1
    end
  end

  describe "mark_active/1" do
    test "flips activated_at from nil to a timestamp", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)
      assert {:ok, active} = Chambers.mark_active(chamber)
      refute is_nil(active.activated_at)
    end

    test "is a no-op once already active", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)
      {:ok, active} = Chambers.mark_active(chamber)
      first_ts = active.activated_at

      assert {:ok, %Chamber{activated_at: ^first_ts}} = Chambers.mark_active(active)
    end
  end

  describe "set_title/2 + set_kind/2" do
    test "set_title updates the title", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)

      assert {:ok, %Chamber{title: "Wani's room"}} =
               Chambers.set_title(chamber, "Wani's room")
    end

    test "set_kind validates against the known kinds", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)
      assert {:ok, %Chamber{kind: "hall"}} = Chambers.set_kind(chamber, "hall")
      assert {:error, %Ecto.Changeset{}} = Chambers.set_kind(chamber, "not-a-kind")
    end
  end

  describe "set_recording/2 + record_events/2 + recorded_events/1" do
    test "set_recording flips the flag", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)
      refute chamber.is_recording

      assert {:ok, on} = Chambers.set_recording(chamber, true)
      assert on.is_recording

      assert {:ok, off} = Chambers.set_recording(on, false)
      refute off.is_recording
    end

    test "record_events bulk-inserts rows with the given timestamps", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)

      t0 = ~U[2026-05-13 12:00:00.000000Z]
      t1 = ~U[2026-05-13 12:00:00.500000Z]
      t2 = ~U[2026-05-13 12:00:01.000000Z]

      assert {:ok, 3} =
               Chambers.record_events(chamber.id, [
                 {%{"instrument" => "drums", "note" => "kick"}, t0},
                 {%{"instrument" => "drums", "note" => "snare"}, t1},
                 {%{"instrument" => "drums", "note" => "hat"}, t2}
               ])

      [a, b, c] = Chambers.recorded_events(chamber.id)
      assert a.payload["note"] == "kick"
      assert b.payload["note"] == "snare"
      assert c.payload["note"] == "hat"
      assert a.inserted_at == t0
      assert b.inserted_at == t1
      assert c.inserted_at == t2
    end

    test "recorded_event_count counts only this chamber's events", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)
      {:ok, other} = Chambers.create_chamber(user.id)

      {:ok, _} =
        Chambers.record_events(chamber.id, [
          {%{"instrument" => "drums"}, DateTime.utc_now()}
        ])

      {:ok, _} =
        Chambers.record_events(other.id, [
          {%{"instrument" => "drums"}, DateTime.utc_now()},
          {%{"instrument" => "drums"}, DateTime.utc_now()}
        ])

      assert Chambers.recorded_event_count(chamber.id) == 1
      assert Chambers.recorded_event_count(other.id) == 2
    end

    test "deleting a chamber cascades its recorded events", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)

      {:ok, _} =
        Chambers.record_events(chamber.id, [
          {%{"instrument" => "drums"}, DateTime.utc_now()}
        ])

      assert Chambers.recorded_event_count(chamber.id) == 1
      {:ok, _} = Chambers.delete(chamber)
      assert Chambers.recorded_event_count(chamber.id) == 0
    end

    test "delete_recorded_events wipes a chamber's events without dropping the chamber",
         %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)

      {:ok, _} =
        Chambers.record_events(chamber.id, [
          {%{"instrument" => "drums"}, DateTime.utc_now()},
          {%{"instrument" => "kendang"}, DateTime.utc_now()}
        ])

      assert Chambers.recorded_event_count(chamber.id) == 2

      assert {2, nil} = Chambers.delete_recorded_events(chamber.id)
      assert Chambers.recorded_event_count(chamber.id) == 0
      # Chamber row itself stays put.
      assert Chambers.find_by_id(chamber.id)
    end
  end

  describe "delete/1 + delete_idle_since/1" do
    test "delete/1 removes the row and emits telemetry", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)

      handler = :"#{__MODULE__}-deleted-#{System.unique_integer([:positive])}"
      test_pid = self()

      :telemetry.attach(
        handler,
        [:mixwave, :chamber, :deleted],
        fn _, _measurements, metadata, _ ->
          send(test_pid, {:deleted_event, metadata})
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      assert {:ok, _} = Chambers.delete(chamber)
      assert is_nil(Chambers.find_by_id(chamber.id))
      assert_receive {:deleted_event, %{slug: slug}}
      assert slug == chamber.slug
    end

    test "delete_idle_since reaps activated, idle, user-owned chambers", %{user: user} do
      ancient = DateTime.utc_now() |> DateTime.add(-48, :hour) |> DateTime.truncate(:second)
      cutoff = DateTime.utc_now() |> DateTime.add(-24, :hour) |> DateTime.truncate(:second)

      {:ok, idle} = Chambers.create_chamber(user.id)

      idle
      |> Ecto.Changeset.change(activated_at: ancient, last_activity_at: ancient)
      |> Repo.update!()

      {:ok, _fresh} = Chambers.create_chamber(user.id)

      assert Chambers.delete_idle_since(cutoff) == 1
      assert is_nil(Chambers.find_by_id(idle.id))
    end

    test "delete_idle_since skips system chambers and fresh-grace ones", %{user: user} do
      cutoff = DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
      ancient = DateTime.utc_now() |> DateTime.add(-48, :hour) |> DateTime.truncate(:second)

      # System chamber — `creator_user_id` is NULL, exempt from
      # the sweeper even at ancient activity.
      {:ok, chaos} = Chambers.ensure_chaos_chamber()
      chaos |> Ecto.Changeset.change(last_activity_at: ancient) |> Repo.update!()

      # Unactivated chamber, still inside the 30-min grace window
      # — owned by the GenServer's `:check_grace` timer, not the
      # sweeper.
      {:ok, unactivated_fresh} = Chambers.create_chamber(user.id)

      assert Chambers.delete_idle_since(cutoff) == 0
      refute is_nil(Chambers.find_by_id(chaos.id))
      refute is_nil(Chambers.find_by_id(unactivated_fresh.id))
    end

    test "delete_idle_since reaps unactivated chambers past their grace window",
         %{user: user} do
      cutoff = DateTime.utc_now() |> DateTime.add(-24, :hour) |> DateTime.truncate(:second)
      past_grace = DateTime.utc_now() |> DateTime.add(-60, :minute) |> DateTime.truncate(:second)

      {:ok, orphan} = Chambers.create_chamber(user.id)

      # Backdate to past the 30-min grace window. Simulates the
      # case where the chamber's GenServer died (BEAM restart,
      # supervisor giving up) before `:check_grace` could fire,
      # leaving the row stranded.
      orphan
      |> Ecto.Changeset.change(inserted_at: past_grace, last_activity_at: past_grace)
      |> Repo.update!()

      assert Chambers.delete_idle_since(cutoff) == 1
      assert is_nil(Chambers.find_by_id(orphan.id))
    end
  end

  describe "touch_activity/1" do
    test "bumps last_activity_at", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)

      chamber
      |> Ecto.Changeset.change(last_activity_at: ~U[2025-01-01 00:00:00Z])
      |> Repo.update!()

      {:ok, touched} = Chambers.touch_activity(chamber)
      assert DateTime.compare(touched.last_activity_at, ~U[2025-01-01 00:00:00Z]) == :gt
    end
  end

  describe "count_chambers/0 + count_activated_chambers/0 + list_all/0" do
    test "totals + activated counts agree with row state", %{user: user} do
      {:ok, c1} = Chambers.create_chamber(user.id)
      {:ok, c2} = Chambers.create_chamber(user.id)
      {:ok, _} = Chambers.mark_active(c1)

      assert Chambers.count_chambers() == 2
      assert Chambers.count_activated_chambers() == 1

      slugs = Chambers.list_all() |> Enum.map(& &1.slug)
      assert c1.slug in slugs
      assert c2.slug in slugs
    end
  end

  describe "list_running/0 + restart_count/1" do
    test "list_running reflects active GenServers", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)
      {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)

      slugs = Chambers.list_running() |> Enum.map(fn {slug, _pid} -> slug end)
      assert chamber.slug in slugs

      stop_chamber(chamber.slug)
    end

    test "restart_count is 0 for a never-restarted slug" do
      assert Chambers.restart_count("nonexistent-slug") == 0
    end
  end

  describe "broadcast_note/2 + activity_topic/0" do
    test "fans the note out on the chamber topic AND the activity topic", %{user: user} do
      {:ok, chamber} = Chambers.create_chamber(user.id)
      {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)

      Phoenix.PubSub.subscribe(Mixwave.PubSub, Chambers.topic(chamber.slug))
      Phoenix.PubSub.subscribe(Mixwave.PubSub, Chambers.activity_topic())

      payload = %{"instrument" => "drums", "style" => "synth", "note" => "kick"}
      :ok = Chambers.broadcast_note(chamber.slug, payload)

      assert_receive {:chamber_note, %{kind: :note, payload: ^payload}}
      assert_receive {:activity, slug, %{payload: ^payload}}
      assert slug == chamber.slug

      stop_chamber(chamber.slug)
    end
  end

  defp stop_chamber(slug) do
    case Registry.lookup(Mixwave.Chambers.Registry, slug) do
      [{pid, _}] ->
        :ok = DynamicSupervisor.terminate_child(Mixwave.Chambers.Supervisor, pid)

      _ ->
        :ok
    end
  end
end
