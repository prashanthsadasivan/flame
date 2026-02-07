defmodule FlameExampleWeb.Router do
  use Phoenix.Router

  import Plug.Conn
  import Phoenix.Controller

  pipeline :api do
    plug :accepts, ["json"]
  end

  scope "/api", FlameExampleWeb do
    pipe_through :api

    # Health check — runs locally, no FLAME involved.
    get "/health", HealthController, :index

    # Synchronous processing via FLAME.call — the response contains the
    # result computed on a remote FLAME runner.
    post "/reports", ReportController, :create
    get "/reports/:id", ReportController, :show

    # Fire-and-forget via FLAME.cast — returns 202 immediately while
    # the work happens asynchronously on a FLAME runner.
    post "/webhooks", WebhookController, :create

    # Long-running background job via FLAME.place_child — starts a
    # GenServer on a FLAME runner and returns the job ID.
    post "/jobs", JobController, :create
    get "/jobs/:id", JobController, :show
  end
end
