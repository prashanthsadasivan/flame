import Config

config :flame_example, FlameExampleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "test-only-secret-key-base-that-is-at-least-64-bytes-long-for-phoenix-to-be-happy-ok",
  server: false

config :logger, level: :warning
