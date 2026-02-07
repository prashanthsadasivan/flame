defmodule FlameExample.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    flame_parent = FLAME.Parent.get()

    children = [
      {Phoenix.PubSub, name: FlameExample.PubSub},

      # A registry to track background jobs started via FLAME.place_child.
      # This runs on both parent and runner nodes so we can look up workers.
      {Registry, keys: :unique, name: FlameExample.JobRegistry},

      # -------------------------------------------------------------------
      # FLAME Pools
      # -------------------------------------------------------------------
      # General-purpose pool for synchronous API request processing.
      # Requests go in, results come back — like a lambda.
      {FLAME.Pool,
       name: FlameExample.RequestRunner,
       min: 0,
       max: 10,
       max_concurrency: 5,
       idle_shutdown_after: :timer.seconds(30),
       log: :debug},

      # Dedicated pool for fire-and-forget background work (webhooks, emails).
      # Higher concurrency because these are typically I/O bound.
      {FLAME.Pool,
       name: FlameExample.BackgroundRunner,
       min: 0,
       max: 5,
       max_concurrency: 20,
       idle_shutdown_after: :timer.seconds(60),
       log: :debug},

      # -------------------------------------------------------------------
      # Phoenix Endpoint — only started on the parent, NOT on FLAME runners.
      # FLAME runners don't need to serve HTTP; they only execute closures.
      # -------------------------------------------------------------------
      !flame_parent && FlameExampleWeb.Endpoint
    ]
    |> Enum.filter(& &1)

    opts = [strategy: :one_for_one, name: FlameExample.Supervisor]
    Supervisor.start_link(children, opts)
  end

  @impl true
  def config_change(changed, _new, removed) do
    FlameExampleWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
