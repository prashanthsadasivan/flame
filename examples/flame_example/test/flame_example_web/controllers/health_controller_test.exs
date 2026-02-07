defmodule FlameExampleWeb.HealthControllerTest do
  use ExUnit.Case

  @moduletag :capture_log

  setup do
    # Start the endpoint for testing
    {:ok, conn: Plug.Test.conn(:get, "/api/health")}
  end

  test "GET /api/health returns ok", %{conn: conn} do
    conn = FlameExampleWeb.Endpoint.call(conn, [])
    assert conn.status == 200

    body = Jason.decode!(conn.resp_body)
    assert body["status"] == "ok"
  end
end
