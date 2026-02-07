defmodule FlameExampleWeb.HealthController do
  @moduledoc """
  A simple health check that runs directly on the parent node.
  No FLAME involvement — this is intentionally lightweight so that
  load balancers and uptime monitors get a fast response.
  """
  use Phoenix.Controller, formats: [:json]

  def index(conn, _params) do
    json(conn, %{
      status: "ok",
      node: to_string(node()),
      flame_parent: FLAME.Parent.get() != nil
    })
  end
end
