defmodule FlameExample.Webhooks do
  @moduledoc """
  Simulated webhook processing context.

  In a real app this might verify signatures, enrich the event with
  data from external APIs, update the database, and send notifications.
  Here we simulate that work with logging and a sleep.

  This runs inside `FLAME.cast/3` — the caller doesn't wait for it.
  """

  require Logger

  @doc """
  Processes an incoming webhook event.

  This function runs on a FLAME runner node. It can take as long as it
  needs — the HTTP response was already sent back to the client.
  """
  def process(source, event, payload) do
    Logger.info("[Webhooks] Processing #{source}/#{event} on #{node()}")
    Logger.info("[Webhooks] Payload: #{inspect(payload)}")

    # Simulate external API calls, DB writes, notification sends
    Process.sleep(500)

    # In a real app you might:
    #   - Verify the webhook signature
    #   - Look up the associated user/account in the DB
    #   - Update subscription status, process payment, etc.
    #   - Send a notification via PubSub
    #   - Call an external API

    Phoenix.PubSub.broadcast(
      FlameExample.PubSub,
      "webhooks:#{source}",
      {:webhook_processed, %{source: source, event: event}}
    )

    Logger.info("[Webhooks] Finished processing #{source}/#{event}")
    :ok
  end
end
