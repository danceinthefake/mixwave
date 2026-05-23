defmodule MixchambWeb.UserAuthTest do
  use Mixchamb.DataCase, async: true

  alias MixchambWeb.UserAuth

  describe "on_mount :current_user" do
    test "assigns the user when the session carries a valid user_id" do
      {:ok, user} = Mixchamb.Accounts.create_anonymous_user()

      {:cont, %{assigns: %{current_user: assigned}}} =
        UserAuth.on_mount(:current_user, %{}, %{"user_id" => user.id}, fresh_socket())

      assert assigned.id == user.id
    end

    test "assigns nil when the session has no user_id (fallback path)" do
      {:cont, %{assigns: %{current_user: nil}}} =
        UserAuth.on_mount(:current_user, %{}, %{}, fresh_socket())
    end
  end

  describe "on_mount :current_admin" do
    test "assigns the admin username when present in the session" do
      {:cont, %{assigns: %{current_admin: "ops-1"}}} =
        UserAuth.on_mount(:current_admin, %{}, %{"admin_username" => "ops-1"}, fresh_socket())
    end

    test "falls back to the env break-glass admin when the session lacks a username" do
      {:cont, %{assigns: %{current_admin: fallback}}} =
        UserAuth.on_mount(:current_admin, %{}, %{}, fresh_socket())

      assert is_binary(fallback)
    end
  end

  describe "on_mount :maybe_admin" do
    test "assigns the admin username when present" do
      {:cont, %{assigns: %{current_admin: "ops-2"}}} =
        UserAuth.on_mount(:maybe_admin, %{}, %{"admin_username" => "ops-2"}, fresh_socket())
    end

    test "stale session with admin_authenticated=true gets the env fallback admin" do
      {:cont, %{assigns: %{current_admin: fallback}}} =
        UserAuth.on_mount(
          :maybe_admin,
          %{},
          %{"admin_authenticated" => true},
          fresh_socket()
        )

      assert is_binary(fallback)
    end

    test "no admin session at all → assigns nil" do
      {:cont, %{assigns: %{current_admin: nil}}} =
        UserAuth.on_mount(:maybe_admin, %{}, %{}, fresh_socket())
    end
  end

  # Build a bare Phoenix.LiveView.Socket — enough surface for the
  # on_mount callbacks to attach assigns to. We don't need a real
  # connected socket for these unit tests.
  defp fresh_socket do
    %Phoenix.LiveView.Socket{assigns: %{__changed__: %{}}}
  end
end
