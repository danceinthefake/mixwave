defmodule Mixwave.RestartWatcherTest do
  use ExUnit.Case, async: false

  alias Mixwave.RestartWatcher

  describe "snapshot/0" do
    test "returns one row per watched module with the expected fields" do
      rows = RestartWatcher.snapshot()
      assert is_list(rows) and length(rows) >= 1

      for row <- rows do
        assert Map.has_key?(row, :module)
        assert Map.has_key?(row, :label)
        assert Map.has_key?(row, :description)
        assert Map.has_key?(row, :pid)
        assert Map.has_key?(row, :count)
        assert is_integer(row.count) and row.count >= 0
      end
    end
  end

  describe "topic/0" do
    test "exposes a stable PubSub topic name" do
      assert RestartWatcher.topic() == "ops:restarts"
    end
  end

  describe ":restarts_changed broadcast" do
    test "subscribers receive a notice when a watched process is killed and restarts" do
      Phoenix.PubSub.subscribe(Mixwave.PubSub, RestartWatcher.topic())

      pid = Process.whereis(Mixwave.Chambers.Sweeper)
      assert is_pid(pid)
      Process.exit(pid, :kill)

      # The watcher monitors the killed pid + bumps the counter +
      # broadcasts. The supervisor restarts the child within ms.
      assert_receive :restarts_changed, 500
    end
  end
end
