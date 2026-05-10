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

    test "delete_idle_since skips system chambers and unactivated ones", %{user: user} do
      cutoff = DateTime.utc_now() |> DateTime.add(-1, :hour) |> DateTime.truncate(:second)
      ancient = DateTime.utc_now() |> DateTime.add(-48, :hour) |> DateTime.truncate(:second)

      {:ok, chaos} = Chambers.ensure_chaos_chamber()
      chaos |> Ecto.Changeset.change(last_activity_at: ancient) |> Repo.update!()

      {:ok, unactivated} = Chambers.create_chamber(user.id)

      unactivated
      |> Ecto.Changeset.change(last_activity_at: ancient)
      |> Repo.update!()

      assert Chambers.delete_idle_since(cutoff) == 0
      refute is_nil(Chambers.find_by_id(chaos.id))
      refute is_nil(Chambers.find_by_id(unactivated.id))
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
