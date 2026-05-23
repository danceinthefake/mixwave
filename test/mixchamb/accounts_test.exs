defmodule Mixchamb.AccountsTest do
  use Mixchamb.DataCase, async: true

  alias Mixchamb.Accounts
  alias Mixchamb.Accounts.AnonymousUser

  describe "create_anonymous_user/1" do
    test "inserts a row with a generated display_name + last_active_at = now" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      assert {:ok, %AnonymousUser{} = user} = Accounts.create_anonymous_user(now)
      assert user.display_name =~ ~r/^[a-z]+-[a-z]+-\d{2}$/
      assert DateTime.compare(user.last_active_at, now) == :eq
    end

    test "two calls produce different user ids" do
      assert {:ok, a} = Accounts.create_anonymous_user()
      assert {:ok, b} = Accounts.create_anonymous_user()
      refute a.id == b.id
    end
  end

  describe "get_anonymous_user/1" do
    test "returns the user when it exists" do
      {:ok, user} = Accounts.create_anonymous_user()
      assert %AnonymousUser{id: id} = Accounts.get_anonymous_user(user.id)
      assert id == user.id
    end

    test "returns nil when missing" do
      assert is_nil(Accounts.get_anonymous_user(Ecto.UUID.generate()))
    end
  end

  describe "touch_anonymous_user/2" do
    test "bumps last_active_at to the supplied time" do
      {:ok, user} = Accounts.create_anonymous_user(~U[2026-01-01 00:00:00Z])
      later = ~U[2026-01-01 00:05:00Z]
      assert {:ok, %{last_active_at: ^later}} = Accounts.touch_anonymous_user(user, later)
    end
  end

  describe "sweep_idle_users/1" do
    test "deletes users whose last_active_at is past the cutoff" do
      ancient = DateTime.utc_now() |> DateTime.add(-48, :hour) |> DateTime.truncate(:second)
      fresh = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, old_user} = Accounts.create_anonymous_user(ancient)
      {:ok, new_user} = Accounts.create_anonymous_user(fresh)

      assert Accounts.sweep_idle_users(24) == 1
      assert is_nil(Accounts.get_anonymous_user(old_user.id))
      assert %AnonymousUser{} = Accounts.get_anonymous_user(new_user.id)
    end

    test "returns 0 when nothing is idle" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      {:ok, _} = Accounts.create_anonymous_user(now)
      assert Accounts.sweep_idle_users(24) == 0
    end
  end

  describe "count_users/0 + count_active_users/1" do
    test "count_users counts all rows; count_active_users honours the window" do
      now = DateTime.utc_now() |> DateTime.truncate(:second)
      stale = DateTime.add(now, -10 * 60, :second)

      {:ok, _} = Accounts.create_anonymous_user(now)
      {:ok, _} = Accounts.create_anonymous_user(stale)

      assert Accounts.count_users() == 2
      # 5-minute window — only the fresh one counts.
      assert Accounts.count_active_users(5) == 1
    end
  end

  describe "list_users/1" do
    test "newest active first, capped at limit" do
      base = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, oldest} = Accounts.create_anonymous_user(DateTime.add(base, -300, :second))
      {:ok, mid} = Accounts.create_anonymous_user(DateTime.add(base, -60, :second))
      {:ok, newest} = Accounts.create_anonymous_user(base)

      results = Accounts.list_users(limit: 10)

      assert Enum.map(results, & &1.id) == [newest.id, mid.id, oldest.id]
    end

    test "respects the limit" do
      for _ <- 1..3, do: {:ok, _} = Accounts.create_anonymous_user()
      assert length(Accounts.list_users(limit: 2)) == 2
    end
  end

  describe "delete_anonymous_user/1" do
    test "removes by struct" do
      {:ok, user} = Accounts.create_anonymous_user()
      assert {:ok, _} = Accounts.delete_anonymous_user(user)
      assert is_nil(Accounts.get_anonymous_user(user.id))
    end

    test "removes by id string" do
      {:ok, user} = Accounts.create_anonymous_user()
      assert {:ok, _} = Accounts.delete_anonymous_user(user.id)
    end

    test "returns :not_found for missing id" do
      assert {:error, :not_found} = Accounts.delete_anonymous_user(Ecto.UUID.generate())
    end
  end

  describe "set_alias/2" do
    test "sets a trimmed alias and leaves display_name untouched" do
      {:ok, user} = Accounts.create_anonymous_user()
      original = user.display_name

      assert {:ok, updated} = Accounts.set_alias(user, "  Bob  ")
      assert updated.alias == "Bob"
      assert updated.display_name == original
    end

    test "blank or whitespace-only alias clears the field" do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, user} = Accounts.set_alias(user, "Bob")

      assert {:ok, %{alias: nil}} = Accounts.set_alias(user, "")
      {:ok, user} = Accounts.set_alias(user, "Bob")
      assert {:ok, %{alias: nil}} = Accounts.set_alias(user, "   ")
    end

    test "rejects an alias longer than 32 chars" do
      {:ok, user} = Accounts.create_anonymous_user()
      assert {:error, changeset} = Accounts.set_alias(user, String.duplicate("a", 33))
      assert "should be at most 32 character(s)" in errors_on(changeset).alias
    end

    test "accepts a 32-char alias exactly at the cap" do
      {:ok, user} = Accounts.create_anonymous_user()
      max = String.duplicate("a", 32)
      assert {:ok, %{alias: ^max}} = Accounts.set_alias(user, max)
    end
  end

  describe "set_last_instrument/2" do
    test "persists the chosen instrument string" do
      {:ok, user} = Accounts.create_anonymous_user()
      assert {:ok, %{last_instrument: "keyboard"}} =
               Accounts.set_last_instrument(user, "keyboard")
    end

    test "no-op when the value is already set to the same" do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, user} = Accounts.set_last_instrument(user, "guitar")
      assert {:ok, ^user} = Accounts.set_last_instrument(user, "guitar")
    end

    test "accepts nil to clear the field" do
      {:ok, user} = Accounts.create_anonymous_user()
      {:ok, user} = Accounts.set_last_instrument(user, "guitar")
      assert {:ok, %{last_instrument: nil}} = Accounts.set_last_instrument(user, nil)
    end
  end
end
