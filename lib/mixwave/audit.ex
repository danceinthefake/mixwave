defmodule Mixwave.Audit do
  @moduledoc """
  Append-only audit log for admin actions. Every action taken
  from the admin LV — kill chamber, delete user, drain node,
  broadcast banner, run sweeper — calls `log_action/4` so a
  later review can answer "who did what, when, to which row."

  The log survives the affected row (no FK back to chambers /
  users), which is the whole point: if a chamber is deleted by
  accident, the audit row tells us who did it.
  """

  import Ecto.Query

  alias Mixwave.Audit.AdminAction
  alias Mixwave.Repo

  @doc """
  Convenience wrapper that auto-fills `admin_user` from the
  configured `:admin_user` env. Use this for actions taken
  outside an LV context (system-driven sweeps, RPC calls,
  break-glass paths) where no logged-in admin is attached.
  """
  def log(action, target, metadata \\ %{}) when is_binary(action) do
    admin = Application.get_env(:mixwave, :admin_user, "admin")
    log_action(action, target, admin, metadata)
  end

  @doc """
  Like `log/3` but takes the admin user explicitly. Admin LVs
  should call this with `socket.assigns.current_admin` so the
  audit row points at the human who took the action instead of
  the catch-all env user.
  """
  def log_as(admin_user, action, target, metadata \\ %{})
      when is_binary(admin_user) and is_binary(action) do
    log_action(action, target, admin_user, metadata)
  end

  @doc """
  Records an admin action. Returns `{:ok, action}` or an Ecto
  error tuple; callers can safely ignore the result if logging
  must never block the actual action.

  Examples:

      Audit.log_action("kill_chamber", "chamber:funky-meerkat", "admin")
      Audit.log_action("broadcast", nil, "admin", %{message: "...", duration_ms: 300_000})
  """
  def log_action(action, target, admin_user, metadata \\ %{})
      when is_binary(action) and is_binary(admin_user) do
    %AdminAction{}
    |> AdminAction.changeset(%{
      action: action,
      target: target,
      admin_user: admin_user,
      metadata: metadata || %{}
    })
    |> Repo.insert()
  end

  @doc """
  Most recent N audit rows, newest first. Drives the Ops tab.
  """
  def recent_actions(limit \\ 100) when is_integer(limit) and limit > 0 do
    AdminAction
    |> order_by([a], desc: a.inserted_at)
    |> limit(^limit)
    |> Repo.all()
  end

  @doc """
  Total audit rows on file — useful for "showing N of M" pager
  hints in the UI.
  """
  def count_actions do
    Repo.aggregate(AdminAction, :count, :id)
  end
end
