defmodule MixchambWeb.HealthControllerTest do
  use MixchambWeb.ConnCase, async: true

  test "GET /up returns 200 JSON ok when the DB is reachable", %{conn: conn} do
    conn = get(conn, ~p"/up")
    assert conn.status == 200
    assert response(conn, 200) =~ "ok"
    assert get_resp_header(conn, "content-type") |> Enum.any?(&(&1 =~ "application/json"))
  end

  test "the probe is public (no admin auth)", %{conn: conn} do
    # No session / admin login set up — still 200.
    assert get(conn, ~p"/up").status == 200
  end
end
