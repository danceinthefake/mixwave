defmodule Mixwave.Accounts.SweeperTest do
  use Mixwave.DataCase, async: false

  alias Mixwave.Accounts
  alias Mixwave.Accounts.Sweeper

  describe "info/0" do
    test "returns a snapshot map with the expected keys" do
      info = Sweeper.info()
      assert is_map(info)
      assert Map.has_key?(info, :last_run_at)
      assert Map.has_key?(info, :last_deleted)
      assert Map.has_key?(info, :threshold_hours)
      assert Map.has_key?(info, :interval_ms)
    end
  end

  describe "sweep_now/0" do
    test "deletes idle users and updates last_run_at" do
      ancient =
        DateTime.utc_now() |> DateTime.add(-48, :hour) |> DateTime.truncate(:second)

      {:ok, user} = Accounts.create_anonymous_user(ancient)

      assert {:ok, deleted} = Sweeper.sweep_now()
      assert deleted >= 1

      assert is_nil(Accounts.get_anonymous_user(user.id))

      info = Sweeper.info()
      refute is_nil(info.last_run_at)
    end
  end
end
