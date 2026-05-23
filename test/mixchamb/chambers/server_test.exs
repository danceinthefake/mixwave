defmodule Mixchamb.Chambers.ServerTest do
  use Mixchamb.DataCase, async: false

  alias Mixchamb.{Accounts, Chambers}
  alias Mixchamb.Chambers.Server

  setup do
    {:ok, user} = Accounts.create_anonymous_user()
    {:ok, chamber} = Chambers.create_chamber(user.id)

    on_exit(fn -> stop_chamber(chamber.slug) end)
    %{user: user, chamber: chamber}
  end

  describe "ensure_started/2" do
    test "starts the GenServer and is idempotent on the same slug", %{chamber: chamber} do
      assert {:ok, pid1} = Server.ensure_started(chamber.slug, chamber.id)
      assert {:ok, pid2} = Server.ensure_started(chamber.slug, chamber.id)
      assert pid1 == pid2
      assert Process.alive?(pid1)
    end

    test "registers the process under the slug via the Registry", %{chamber: chamber} do
      {:ok, pid} = Server.ensure_started(chamber.slug, chamber.id)
      assert [{^pid, _}] = Registry.lookup(Mixchamb.Chambers.Registry, chamber.slug)
    end
  end

  describe "record/2 + recent_events/1 + recent_events_within/2" do
    test "buffered events come back in chronological order", %{chamber: chamber} do
      {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)

      Server.record(chamber.slug, %{kind: :note, at: 1, payload: %{n: 1}})
      Server.record(chamber.slug, %{kind: :note, at: 2, payload: %{n: 2}})
      Server.record(chamber.slug, %{kind: :note, at: 3, payload: %{n: 3}})

      events = Server.recent_events(chamber.slug)
      assert Enum.map(events, & &1.payload.n) == [1, 2, 3]
    end

    test "recent_events_within filters by monotonic time", %{chamber: chamber} do
      {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)
      now = System.monotonic_time(:millisecond)

      Server.record(chamber.slug, %{kind: :note, at: now - 60_000, payload: :old})
      Server.record(chamber.slug, %{kind: :note, at: now - 1_000, payload: :recent})

      payloads = Server.recent_events_within(chamber.slug, 30) |> Enum.map(& &1.payload)
      assert payloads == [:recent]
    end
  end

  describe "info/1" do
    test "reports event count + uptime + slug", %{chamber: chamber} do
      {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)
      Server.record(chamber.slug, %{kind: :note, at: 0, payload: :a})
      Server.record(chamber.slug, %{kind: :note, at: 0, payload: :b})

      info = Server.info(chamber.slug)
      assert info.slug == chamber.slug
      assert info.event_count == 2
      assert is_integer(info.uptime_ms) and info.uptime_ms >= 0
    end

    test "returns nil if the slug isn't running" do
      assert is_nil(Server.info("not-a-real-slug"))
    end
  end

  describe ":transient restart strategy" do
    test "abnormal exit causes the supervisor to restart the chamber", %{chamber: chamber} do
      {:ok, pid1} = Server.ensure_started(chamber.slug, chamber.id)
      ref = Process.monitor(pid1)

      Process.exit(pid1, :kill)
      assert_receive {:DOWN, ^ref, :process, ^pid1, _}, 500

      # Give the supervisor a beat to bring it back.
      :timer.sleep(50)

      [{pid2, _}] = Registry.lookup(Mixchamb.Chambers.Registry, chamber.slug)
      assert Process.alive?(pid2)
      refute pid2 == pid1

      assert Chambers.restart_count(chamber.slug) >= 1
    end

    test "{:stop, :normal, _} doesn't trigger a restart", %{chamber: chamber} do
      {:ok, pid} = Server.ensure_started(chamber.slug, chamber.id)
      ref = Process.monitor(pid)

      :ok = DynamicSupervisor.terminate_child(Mixchamb.Chambers.Supervisor, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 500

      :timer.sleep(50)
      assert [] == Registry.lookup(Mixchamb.Chambers.Registry, chamber.slug)
    end
  end

  describe "poker casts" do
    setup %{chamber: chamber} do
      # Start the GenServer first, THEN switch activity so the
      # in-process state actually allocates a PokerSession.
      {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)
      Server.set_activity(chamber.slug, "poker")
      :timer.sleep(20)
      :ok
    end

    test "poker_vote stores the vote", %{chamber: chamber, user: user} do
      Server.poker_vote(chamber.slug, user.id, "5")
      :timer.sleep(20)
      assert Server.poker_state(chamber.slug).votes[user.id] == "5"
    end

    test "poker_withdraw_vote drops the vote", %{chamber: chamber, user: user} do
      Server.poker_vote(chamber.slug, user.id, "5")
      Server.poker_withdraw_vote(chamber.slug, user.id)
      :timer.sleep(20)
      refute Map.has_key?(Server.poker_state(chamber.slug).votes, user.id)
    end

    test "poker_reveal flips status", %{chamber: chamber} do
      Server.poker_reveal(chamber.slug)
      :timer.sleep(20)
      assert Server.poker_state(chamber.slug).status == :revealed
    end

    test "poker_revote clears votes + returns to voting", %{chamber: chamber, user: user} do
      Server.poker_vote(chamber.slug, user.id, "5")
      Server.poker_reveal(chamber.slug)
      :timer.sleep(20)

      Server.poker_revote(chamber.slug)
      :timer.sleep(20)

      session = Server.poker_state(chamber.slug)
      assert session.status == :voting
      assert session.votes == %{}
    end

    test "poker_next_round bumps the round counter", %{chamber: chamber} do
      Server.poker_next_round(chamber.slug)
      :timer.sleep(20)
      assert Server.poker_state(chamber.slug).round == 2
    end

    test "poker_set_story updates the story", %{chamber: chamber} do
      Server.poker_set_story(chamber.slug, "Migrate auth")
      :timer.sleep(20)
      assert Server.poker_state(chamber.slug).story == "Migrate auth"
    end

    test "poker_set_deck switches deck when no votes", %{chamber: chamber} do
      Server.poker_set_deck(chamber.slug, :tshirt)
      :timer.sleep(20)
      assert Server.poker_state(chamber.slug).deck == :tshirt
    end

    test "poker_set_queue replaces the queue", %{chamber: chamber} do
      Server.poker_set_queue(chamber.slug, ["one", "two"])
      :timer.sleep(20)
      assert Server.poker_state(chamber.slug).queue == ["one", "two"]
    end
  end

  describe "set_activity cast" do
    test "music → poker allocates a fresh PokerSession + broadcasts",
         %{chamber: chamber} do
      :ok = Phoenix.PubSub.subscribe(Mixchamb.PubSub, Mixchamb.Chambers.topic(chamber.slug))

      {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)
      assert is_nil(Server.poker_state(chamber.slug))

      Server.set_activity(chamber.slug, "poker")
      assert_receive {:activity_changed, "poker"}, 500
      assert %Mixchamb.Chambers.PokerSession{} = Server.poker_state(chamber.slug)
    end

    test "poker → music drops the PokerSession", %{chamber: chamber} do
      {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)
      Server.set_activity(chamber.slug, "poker")
      :timer.sleep(20)
      assert Server.poker_state(chamber.slug)

      Server.set_activity(chamber.slug, "music")
      :timer.sleep(20)
      assert is_nil(Server.poker_state(chamber.slug))
    end
  end

  describe "host management" do
    setup %{chamber: chamber} = ctx do
      {:ok, _pid} = Server.ensure_started(chamber.slug, chamber.id)
      {:ok, other} = Accounts.create_anonymous_user()
      {:ok, third} = Accounts.create_anonymous_user()
      Map.merge(ctx, %{other: other, third: third})
    end

    test "creator starts as the sole host", %{chamber: chamber, user: creator} do
      assert Server.hosts(chamber.slug) == [creator.id]
    end

    test "creator can promote another participant", %{
      chamber: chamber,
      user: creator,
      other: other
    } do
      :ok = Phoenix.PubSub.subscribe(Mixchamb.PubSub, Mixchamb.Chambers.topic(chamber.slug))
      Server.promote_host(chamber.slug, creator.id, other.id)
      assert_receive {:hosts_changed, hosts}, 500
      assert Enum.sort(hosts) == Enum.sort([creator.id, other.id])
      assert Enum.sort(Server.hosts(chamber.slug)) == Enum.sort([creator.id, other.id])
    end

    test "non-creator can't promote anyone", %{
      chamber: chamber,
      other: other,
      third: third
    } do
      Server.promote_host(chamber.slug, other.id, third.id)
      # Wait a beat to be sure no broadcast fired.
      :timer.sleep(50)
      refute third.id in Server.hosts(chamber.slug)
    end

    test "promoting an existing host is a no-op", %{
      chamber: chamber,
      user: creator,
      other: other
    } do
      Server.promote_host(chamber.slug, creator.id, other.id)
      :timer.sleep(20)
      hosts_before = Server.hosts(chamber.slug)
      Server.promote_host(chamber.slug, creator.id, other.id)
      :timer.sleep(20)
      assert Enum.sort(Server.hosts(chamber.slug)) == Enum.sort(hosts_before)
    end

    test "creator can demote a co-host", %{
      chamber: chamber,
      user: creator,
      other: other
    } do
      Server.promote_host(chamber.slug, creator.id, other.id)
      :timer.sleep(20)
      Server.demote_host(chamber.slug, creator.id, other.id)
      :timer.sleep(20)
      assert Server.hosts(chamber.slug) == [creator.id]
    end

    test "creator can't demote themselves", %{chamber: chamber, user: creator} do
      Server.demote_host(chamber.slug, creator.id, creator.id)
      :timer.sleep(50)
      assert creator.id in Server.hosts(chamber.slug)
    end

    test "co-host can demote themselves", %{
      chamber: chamber,
      user: creator,
      other: other
    } do
      Server.promote_host(chamber.slug, creator.id, other.id)
      :timer.sleep(20)
      Server.demote_host(chamber.slug, other.id, other.id)
      :timer.sleep(20)
      refute other.id in Server.hosts(chamber.slug)
    end

    test "co-host can't demote a different co-host", %{
      chamber: chamber,
      user: creator,
      other: other,
      third: third
    } do
      Server.promote_host(chamber.slug, creator.id, other.id)
      Server.promote_host(chamber.slug, creator.id, third.id)
      :timer.sleep(20)

      Server.demote_host(chamber.slug, other.id, third.id)
      :timer.sleep(50)
      # third stays a host — non-creator can only demote self.
      assert third.id in Server.hosts(chamber.slug)
    end
  end

  defp stop_chamber(slug) do
    case Registry.lookup(Mixchamb.Chambers.Registry, slug) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(Mixchamb.Chambers.Supervisor, pid)

      _ ->
        :ok
    end
  end
end
