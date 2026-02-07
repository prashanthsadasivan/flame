import Config

config :flame_example, FlameExampleWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4000],
  check_origin: false,
  debug_errors: true,
  secret_key_base: "dev-only-secret-key-base-that-is-at-least-64-bytes-long-for-phoenix-to-be-happy-ok",
  watchers: []

# FLAME uses LocalBackend in dev by default — no extra config needed.
# Functions passed to FLAME.call/cast will just execute locally.

config :logger, :console, format: "[$level] $message\n"
