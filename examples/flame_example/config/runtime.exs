import Config

if config_env() == :prod do
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"
  port = String.to_integer(System.get_env("PORT") || "4000")

  config :flame_example, FlameExampleWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      ip: {0, 0, 0, 0, 0, 0, 0, 0},
      port: port
    ],
    secret_key_base: secret_key_base,
    server: !FLAME.Parent.get()

  # Configure FLAME to use the Fly backend in production.
  # FLAME runners don't serve HTTP (server: false above) — they only
  # execute the closures sent via FLAME.call/cast/place_child.
  config :flame, :backend, FLAME.FlyBackend

  config :flame, FLAME.FlyBackend,
    token: System.fetch_env!("FLY_API_TOKEN"),
    env: %{
      "SECRET_KEY_BASE" => secret_key_base,
      "PHX_HOST" => host
    }
end
