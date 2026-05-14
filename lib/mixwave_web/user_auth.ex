defmodule MixwaveWeb.UserAuth do
  @moduledoc """
  LiveView authentication helpers.

  The HTTP-side plug (`MixwaveWeb.Plugs.EnsureAnonUser`) creates the
  anonymous user before any page renders, so by the time a LiveView
  WebSocket connects, the session already carries `user_id`. This
  module's `on_mount` callback pulls that id back into a struct in
  the LV socket assigns.
  """
  import Phoenix.Component, only: [assign: 3]

  alias Mixwave.Accounts

  @doc """
  on_mount callback. Wire into a LiveView with:

      use MixwaveWeb, :live_view
      on_mount {MixwaveWeb.UserAuth, :current_user}

  Or, more commonly, attach to a `live_session` in the router so a
  whole group of LVs share it.
  """
  def on_mount(:current_user, _params, %{"user_id" => user_id}, socket)
      when is_binary(user_id) do
    user = Accounts.get_anonymous_user(user_id)
    {:cont, assign(socket, :current_user, user)}
  end

  def on_mount(:current_user, _params, _session, socket) do
    # Shouldn't happen in normal flow — every browser request runs
    # through EnsureAnonUser before the LV mounts. Mount with nil
    # user rather than crashing so the page at least renders.
    {:cont, assign(socket, :current_user, nil)}
  end

  # `:current_admin` variant — wired into the :admin live_session
  # in the router. Pulls `:admin_username` out of the session
  # into the LV's `:current_admin` assign so handlers can
  # attribute audit rows to the human (or env break-glass user)
  # who's logged in.
  def on_mount(:current_admin, _params, %{"admin_username" => username}, socket)
      when is_binary(username) do
    {:cont, assign(socket, :current_admin, username)}
  end

  def on_mount(:current_admin, _params, _session, socket) do
    # Should never happen — AdminAuth blocks the request before
    # the LV mounts. Fall back to the env user so an audit row
    # never carries nil.
    fallback = Application.get_env(:mixwave, :admin_user, "admin")
    {:cont, assign(socket, :current_admin, fallback)}
  end
end
