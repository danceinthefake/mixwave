defmodule Mixwave.Chambers.SweeperTest do
  use Mixwave.DataCase, async: false

  alias Mixwave.{Accounts, Chambers}
  alias Mixwave.Chambers.Sweeper

  describe "info/0" do
    test "returns a snapshot map" do
      info = Sweeper.info()
      assert is_map(info)
      assert Map.has_key?(info, :last_run_at)
      assert Map.has_key?(info, :last_deleted)
      assert Map.has_key?(info, :threshold_hours)
    end
  end

  describe "sweep_now/0" do
    test "deletes idle activated chambers but keeps fresh ones" do
      {:ok, user} = Accounts.create_anonymous_user()

      ancient =
        DateTime.utc_now() |> DateTime.add(-48, :hour) |> DateTime.truncate(:second)

      {:ok, idle} = Chambers.create_chamber(user.id)

      idle
      |> Ecto.Changeset.change(activated_at: ancient, last_activity_at: ancient)
      |> Repo.update!()

      {:ok, fresh} = Chambers.create_chamber(user.id)

      assert {:ok, deleted} = Sweeper.sweep_now()
      assert deleted >= 1

      assert is_nil(Chambers.find_by_id(idle.id))
      refute is_nil(Chambers.find_by_id(fresh.id))
    end
  end
end
