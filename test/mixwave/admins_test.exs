defmodule Mixwave.AdminsTest do
  use Mixwave.DataCase, async: true

  alias Mixwave.Admins

  describe "create_admin/1" do
    test "persists with a bcrypt hash + clears the virtual password" do
      assert {:ok, admin} = Admins.create_admin(%{username: "kiki", password: "supersecret"})

      assert admin.username == "kiki"
      assert is_binary(admin.password_hash)
      assert admin.password == nil
    end

    test "rejects short passwords" do
      assert {:error, changeset} = Admins.create_admin(%{username: "x", password: "short"})
      assert "should be at most 32 character(s)" not in errors_on(changeset).username
      assert "should be at least 8 character(s)" in errors_on(changeset).password
    end

    test "rejects duplicate usernames (case-insensitive)" do
      {:ok, _} = Admins.create_admin(%{username: "kiki", password: "supersecret"})

      assert {:error, changeset} =
               Admins.create_admin(%{username: "KIKI", password: "supersecret"})

      assert "has already been taken" in errors_on(changeset).username
    end
  end

  describe "authenticate/2" do
    test "returns the row + stamps last_login_at on success" do
      {:ok, _} = Admins.create_admin(%{username: "kiki", password: "supersecret"})

      assert %{username: "kiki", last_login_at: ts} = Admins.authenticate("kiki", "supersecret")
      assert %DateTime{} = ts
    end

    test "is case-insensitive on username via citext" do
      {:ok, _} = Admins.create_admin(%{username: "kiki", password: "supersecret"})
      assert %{username: "kiki"} = Admins.authenticate("KIKI", "supersecret")
    end

    test "returns nil on wrong password" do
      {:ok, _} = Admins.create_admin(%{username: "kiki", password: "supersecret"})
      assert Admins.authenticate("kiki", "wrong") == nil
    end

    test "returns nil on unknown username" do
      assert Admins.authenticate("nobody", "supersecret") == nil
    end
  end

  describe "delete_admin/1 + change_password/2" do
    test "delete by struct" do
      {:ok, admin} = Admins.create_admin(%{username: "kiki", password: "supersecret"})
      assert {:ok, _} = Admins.delete_admin(admin)
      assert Admins.get_admin(admin.id) == nil
    end

    test "delete by id returns :not_found when missing" do
      assert {:error, :not_found} = Admins.delete_admin(Ecto.UUID.generate())
    end

    test "change_password updates the hash and accepts the new one" do
      {:ok, admin} = Admins.create_admin(%{username: "kiki", password: "supersecret"})
      old_hash = admin.password_hash

      assert {:ok, updated} = Admins.change_password(admin, "newsupersecret")
      assert updated.password_hash != old_hash
      assert %{username: "kiki"} = Admins.authenticate("kiki", "newsupersecret")
    end
  end
end
