defmodule FlameExampleWeb.Endpoint do
  use Phoenix.Endpoint, otp_app: :flame_example

  @session_options [
    store: :cookie,
    key: "_flame_example_key",
    signing_salt: "flame_salt",
    same_site: "Lax"
  ]

  plug Plug.RequestId
  plug Plug.Telemetry, event_prefix: [:phoenix, :endpoint]

  plug Plug.Parsers,
    parsers: [:urlencoded, :json],
    pass: ["*/*"],
    json_decoder: Phoenix.json_library()

  plug Plug.MethodOverride
  plug Plug.Head
  plug Plug.Session, @session_options
  plug FlameExampleWeb.Router
end
