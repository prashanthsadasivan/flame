import Config

config :flame_example, FlameExampleWeb.Endpoint,
  url: [host: "localhost"],
  render_errors: [formats: [json: FlameExampleWeb.ErrorJSON], layout: false],
  pubsub_server: FlameExample.PubSub,
  server: true

config :logger, :console,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

config :phoenix, :json_library, Jason

import_config "#{config_env()}.exs"
