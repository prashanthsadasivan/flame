defmodule FlameExampleWeb.WebhookController do
  @moduledoc """
  Demonstrates fire-and-forget processing with `FLAME.cast/3`.

  The endpoint acknowledges the webhook immediately with 202 Accepted,
  then the actual processing happens asynchronously on a FLAME runner.
  The client doesn't wait — ideal for webhooks, email sending, analytics
  event ingestion, and other "enqueue and forget" patterns.
  """
  use Phoenix.Controller, formats: [:json]

  require Logger

  # POST /api/webhooks
  def create(conn, params) do
    source = params["source"] || "unknown"
    event = params["event"] || "ping"
    payload = params["payload"] || %{}

    # ------------------------------------------------------------------
    # FLAME.cast/3 — fire and forget.
    #
    # The closure is sent to a runner and executed asynchronously.
    # We don't wait for it to complete. The runner handles retries,
    # logging, side effects, etc.
    # ------------------------------------------------------------------
    FLAME.cast(FlameExample.BackgroundRunner, fn ->
      Logger.info("Processing webhook from #{source}: #{event} on node #{node()}")
      FlameExample.Webhooks.process(source, event, payload)
    end)

    conn
    |> put_status(:accepted)
    |> json(%{
      status: "accepted",
      message: "Webhook queued for processing on a FLAME runner"
    })
  end
end
