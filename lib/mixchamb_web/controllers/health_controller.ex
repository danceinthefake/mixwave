defmodule MixchambWeb.HealthController do
  @moduledoc """
  Lightweight `GET /up` readiness probe for load balancers and uptime
  monitors. No session / CSRF / LiveView — just a single `SELECT 1` to
  confirm the database is reachable. 200 `{"status":"ok"}` when healthy,
  503 `{"status":"error"}` otherwise (so a probe can route traffic away
  from an origin whose DB is down).

  The human-facing admin health view lives at `/admin/health`.
  """
  use MixchambWeb, :controller

  def show(conn, _params) do
    conn = put_resp_content_type(conn, "application/json")

    if db_ok?() do
      send_resp(conn, 200, ~s({"status":"ok"}))
    else
      send_resp(conn, 503, ~s({"status":"error"}))
    end
  end

  defp db_ok? do
    case Ecto.Adapters.SQL.query(Mixchamb.Repo, "SELECT 1", []) do
      {:ok, _} -> true
      _ -> false
    end
  rescue
    _ -> false
  end
end
