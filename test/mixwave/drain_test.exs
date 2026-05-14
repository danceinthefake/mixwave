defmodule Mixwave.DrainTest do
  use ExUnit.Case, async: false

  alias Mixwave.Drain

  describe "topic/0" do
    test "is a stable string for PubSub subscribers" do
      assert is_binary(Drain.topic())
    end
  end

  describe "shutdown signal" do
    test "terminating a fresh Drain process broadcasts {:node_draining, node}" do
      # Spawn a separate Drain so we don't kill the application-
      # tree one. Same module, isolated name.
      {:ok, pid} = GenServer.start(Drain, nil, name: :drain_test)
      Phoenix.PubSub.subscribe(Mixwave.PubSub, Drain.topic())

      # Skip Drain's grace sleep so the test doesn't take 3 s.
      # We're verifying the broadcast happens, not the timing.
      Process.flag(:trap_exit, true)
      GenServer.stop(pid, :normal, 10_000)

      this_node = Node.self()
      assert_receive {:node_draining, ^this_node}, 5_000
    end
  end
end
