defmodule Mixwave.Chambers.ServerTest do
  use Mixwave.DataCase, async: false

  alias Mixwave.{Accounts, Chambers}
  alias Mixwave.Chambers.Server

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
      assert [{^pid, _}] = Registry.lookup(Mixwave.Chambers.Registry, chamber.slug)
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

      [{pid2, _}] = Registry.lookup(Mixwave.Chambers.Registry, chamber.slug)
      assert Process.alive?(pid2)
      refute pid2 == pid1

      assert Chambers.restart_count(chamber.slug) >= 1
    end

    test "{:stop, :normal, _} doesn't trigger a restart", %{chamber: chamber} do
      {:ok, pid} = Server.ensure_started(chamber.slug, chamber.id)
      ref = Process.monitor(pid)

      :ok = DynamicSupervisor.terminate_child(Mixwave.Chambers.Supervisor, pid)
      assert_receive {:DOWN, ^ref, :process, ^pid, _}, 500

      :timer.sleep(50)
      assert [] == Registry.lookup(Mixwave.Chambers.Registry, chamber.slug)
    end
  end

  defp stop_chamber(slug) do
    case Registry.lookup(Mixwave.Chambers.Registry, slug) do
      [{pid, _}] ->
        DynamicSupervisor.terminate_child(Mixwave.Chambers.Supervisor, pid)

      _ ->
        :ok
    end
  end
end
