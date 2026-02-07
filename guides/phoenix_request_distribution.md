# Distributing Phoenix API Requests with FLAME

## The Short Answer

Yes, you can use FLAME to offload Phoenix API request processing to a pool of
remote servers. However, FLAME is **not a load balancer** — it does not distribute
incoming HTTP connections across machines. Instead, your Phoenix endpoint still
receives every request on the main node, and you use `FLAME.call/3` inside your
controllers (or plugs) to execute the heavy work on an elastically scaled pool of
runner nodes. The result is returned to the caller and sent back as the HTTP
response.

This is a powerful pattern: your "web tier" stays thin and responsive while
arbitrarily expensive work fans out to short-lived infrastructure that scales to
zero when idle.

## Architecture Overview

```
                          ┌──────────────────────┐
                          │   Load Balancer /     │
                          │   Fly Proxy / etc.    │
                          └──────────┬───────────┘
                                     │
                          ┌──────────▼───────────┐
                          │  Phoenix Endpoint     │
                          │  (receives HTTP)      │
                          │                       │
                          │  Controller calls     │
                          │  FLAME.call(pool, fn) │
                          └──────────┬───────────┘
                                     │
                    ┌────────────────┼────────────────┐
                    │                │                │
              ┌─────▼─────┐   ┌─────▼─────┐   ┌─────▼─────┐
              │  Runner 1  │   │  Runner 2  │   │  Runner 3  │
              │  (FLAME    │   │  (FLAME    │   │  (FLAME    │
              │   node)    │   │   node)    │   │   node)    │
              └───────────┘   └───────────┘   └───────────┘
                    ▲                ▲                ▲
                    │  elastically scaled, auto-destroyed
                    │  each is a full copy of your app
```

The Phoenix endpoint runs on your main server(s). When a request arrives, the
controller wraps the work in `FLAME.call/3`. FLAME picks a runner from the pool
(or boots a new one), ships the closure over Erlang distribution, executes it,
and returns the result. The controller then sends the HTTP response.

## Step-by-Step Setup

### 1. Add FLAME to your Phoenix project

```elixir
# mix.exs
defp deps do
  [
    {:phoenix, "~> 1.7"},
    {:flame, "~> 0.5"},
    # ...
  ]
end
```

### 2. Configure a FLAME pool in your application supervision tree

```elixir
# lib/my_app/application.ex
defmodule MyApp.Application do
  use Application

  @impl true
  def start(_type, _args) do
    flame_parent = FLAME.Parent.get()

    children = [
      MyApp.Repo,
      {DNSCluster, query: Application.get_env(:my_app, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: MyApp.PubSub},

      # FLAME pool for distributing API request work
      {FLAME.Pool,
       name: MyApp.APIRunner,
       min: 0,
       max: 10,
       max_concurrency: 20,
       idle_shutdown_after: :timer.seconds(30),
       log: :debug},

      # Only start the web endpoint on the parent node, not on FLAME runners
      !flame_parent && MyAppWeb.Endpoint
    ]
    |> Enum.filter(& &1)

    opts = [strategy: :one_for_one, name: MyApp.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
```

Key configuration choices:
- **`min: 0`** — Scale to zero. No runners are kept alive when there is no traffic.
- **`max: 10`** — Up to 10 runner nodes can be booted.
- **`max_concurrency: 20`** — Each runner handles up to 20 concurrent requests
  before the pool boots another runner.
- **`idle_shutdown_after`** — Runners shut down after 30s of inactivity.
- **`!flame_parent && MyAppWeb.Endpoint`** — FLAME runners do NOT serve HTTP.
  They only execute the closures sent to them.

### 3. Configure the backend for production

```elixir
# config/runtime.exs
if config_env() == :prod do
  config :flame, :backend, FLAME.FlyBackend

  config :flame, FLAME.FlyBackend,
    token: System.fetch_env!("FLY_API_TOKEN"),
    cpu_kind: "performance",
    cpus: 2,
    memory_mb: 2048,
    env: %{
      "DATABASE_URL" => System.fetch_env!("DATABASE_URL"),
      "SECRET_KEY_BASE" => System.fetch_env!("SECRET_KEY_BASE"),
      "POOL_SIZE" => "2"
    }
end
```

In dev/test, FLAME uses `FLAME.LocalBackend` by default, which simply runs the
function locally — no extra configuration needed.

### 4. Reduce database pool size on FLAME runners

Since FLAME runners are ephemeral and only handle a few concurrent operations,
they don't need a large database pool:

```elixir
# config/runtime.exs
pool_size =
  if FLAME.Parent.get() do
    2
  else
    String.to_integer(System.get_env("POOL_SIZE") || "10")
  end

config :my_app, MyApp.Repo,
  pool_size: pool_size
```

### 5. Use FLAME.call in your controllers

This is where the distribution happens. Wrap the request processing logic in
`FLAME.call/3`:

```elixir
defmodule MyAppWeb.ReportController do
  use MyAppWeb, :controller

  def generate(conn, %{"id" => id}) do
    # The entire closure runs on a remote FLAME node.
    # The `id` variable is captured and sent along automatically.
    result =
      FLAME.call(MyApp.APIRunner, fn ->
        report = MyApp.Reports.build_complex_report(id)
        # Repo calls work because the FLAME node booted the full app
        MyApp.Reports.save_report(report)
        report
      end)

    json(conn, %{data: result})
  end
end
```

That's it. The `conn` stays on the parent node. Only the function closure is
shipped to the runner. When the runner finishes, the result is returned to the
controller which sends the JSON response.

## Practical Patterns

### Pattern 1: Offload Only Heavy Work

The simplest and most common pattern — keep lightweight request handling local
and only offload expensive operations:

```elixir
defmodule MyAppWeb.ImageController do
  use MyAppWeb, :controller

  def create(conn, %{"image" => upload}) do
    # Read the upload locally (fast, I/O bound to the client connection)
    image_data = File.read!(upload.path)

    # Offload CPU-intensive image processing to a FLAME runner
    {:ok, urls} =
      FLAME.call(MyApp.APIRunner, fn ->
        thumbnails = MyApp.Images.generate_thumbnails(image_data)
        urls = MyApp.Storage.upload_all(thumbnails)
        MyApp.Repo.insert_all(Image, Enum.map(urls, &%{url: &1}))
        {:ok, urls}
      end)

    json(conn, %{thumbnails: urls})
  end
end
```

### Pattern 2: Wrap Entire Controller Actions

For APIs where every request is roughly equally expensive (e.g., an AI inference
API), you can wrap the entire action body:

```elixir
defmodule MyAppWeb.InferenceController do
  use MyAppWeb, :controller

  def predict(conn, params) do
    result =
      FLAME.call(MyApp.APIRunner, fn ->
        model = MyApp.ML.load_model(params["model"])
        MyApp.ML.predict(model, params["input"])
      end)

    json(conn, %{prediction: result})
  end
end
```

### Pattern 3: A Plug for Blanket Distribution

If you want *all* requests to a specific pipeline to be processed on FLAME
runners, you can write a Plug:

```elixir
defmodule MyAppWeb.Plugs.FlameCall do
  @moduledoc """
  A Plug that executes the downstream pipeline on a FLAME runner.

  Only the processing logic runs remotely — the conn is read on the
  parent node, serializable params are sent to the runner, and the
  result is mapped back onto the conn.
  """
  import Plug.Conn

  def init(opts), do: opts

  def call(conn, opts) do
    pool = Keyword.fetch!(opts, :pool)

    # Extract only what the runner needs (conn is NOT serializable as-is
    # because it holds the socket/adapter state)
    request = %{
      method: conn.method,
      path: conn.request_path,
      params: conn.params,
      headers: conn.req_headers
    }

    {status, response_body, response_headers} =
      FLAME.call(pool, fn ->
        # Perform your business logic using request data
        # This is where you'd call into your context modules
        MyApp.API.handle_request(request)
      end)

    conn
    |> merge_resp_headers(response_headers)
    |> send_resp(status, response_body)
    |> halt()
  end
end
```

Usage in your router:

```elixir
pipeline :flame_api do
  plug :accepts, ["json"]
  plug MyAppWeb.Plugs.FlameCall, pool: MyApp.APIRunner
end
```

> **Important caveat:** `Plug.Conn` is not fully serializable across nodes
> because it holds socket/adapter references. You should extract the data you need
> (params, headers, body) before the FLAME call and reconstruct the response
> afterward. Don't try to send the entire `conn` into the closure.

### Pattern 4: Fire-and-Forget with FLAME.cast

For requests where the client doesn't need to wait for completion (e.g., webhook
processing, sending emails, analytics ingestion):

```elixir
defmodule MyAppWeb.WebhookController do
  use MyAppWeb, :controller

  def handle(conn, params) do
    # Acknowledge immediately, process in the background on a FLAME runner
    FLAME.cast(MyApp.APIRunner, fn ->
      MyApp.Webhooks.process(params)
    end)

    send_resp(conn, 202, "accepted")
  end
end
```

### Pattern 5: Long-Running Workers via place_child

For requests that kick off long-running background processes (e.g., a video
transcode job that reports progress via PubSub):

```elixir
defmodule MyAppWeb.TranscodeController do
  use MyAppWeb, :controller

  def create(conn, %{"video_id" => video_id}) do
    {:ok, _pid} =
      FLAME.place_child(MyApp.APIRunner, {MyApp.TranscodeWorker, video_id: video_id})

    json(conn, %{status: "processing", video_id: video_id})
  end
end
```

The `TranscodeWorker` GenServer runs on the FLAME node but can broadcast
progress via `Phoenix.PubSub` because the full app (including PubSub) is
running on the runner.

## Multiple Pools for Different Workloads

You can define separate pools with different resource profiles for different
kinds of API work:

```elixir
# lib/my_app/application.ex
children = [
  # Lightweight API work — many concurrent, small machines
  {FLAME.Pool,
   name: MyApp.LightRunner,
   min: 0,
   max: 20,
   max_concurrency: 50,
   idle_shutdown_after: :timer.seconds(30)},

  # Heavy computation — fewer, bigger machines
  {FLAME.Pool,
   name: MyApp.HeavyRunner,
   backend: {FLAME.FlyBackend, cpus: 8, memory_mb: 16384},
   min: 0,
   max: 5,
   max_concurrency: 2,
   idle_shutdown_after: :timer.minutes(2)},

  # GPU inference
  {FLAME.Pool,
   name: MyApp.GPURunner,
   backend: {FLAME.FlyBackend, gpu_kind: "a100-pcie-40gb", cpus: 8, memory_mb: 32768},
   min: 0,
   max: 3,
   max_concurrency: 4,
   idle_shutdown_after: :timer.minutes(5)},
]
```

Then route requests to the appropriate pool in your controllers:

```elixir
# Light work
FLAME.call(MyApp.LightRunner, fn -> ... end)

# Heavy work
FLAME.call(MyApp.HeavyRunner, fn -> ... end)

# GPU inference
FLAME.call(MyApp.GPURunner, fn -> ... end)
```

## What About Distributing HTTP Connections Themselves?

If your goal is to spread incoming HTTP connections across multiple machines
(classic horizontal scaling), that is the job of a **load balancer**, not FLAME.
Use your infrastructure's load balancer (e.g., Fly Proxy, AWS ALB, nginx) to
distribute connections across multiple instances of your Phoenix app.

FLAME solves a *different* problem: **elastic compute for specific operations**.
It complements a load balancer — your load-balanced Phoenix instances each have
access to a shared FLAME pool that can burst to handle spikes in expensive work.

```
Traditional horizontal scaling:
  Load Balancer → Phoenix 1, Phoenix 2, Phoenix 3  (all serve HTTP)

FLAME pattern:
  Load Balancer → Phoenix 1, Phoenix 2  (serve HTTP, stay lightweight)
                     ↓           ↓
                  FLAME Pool (0-N runners, elastic, no HTTP)
```

The FLAME approach can be more cost-effective because:
- Your web tier stays small (only needs to handle connections + light I/O)
- Expensive compute scales independently and to zero
- You don't pay for idle GPU/CPU machines when traffic is low

## Timeouts and Error Handling

Configure timeouts appropriate for your API SLAs:

```elixir
# Per-pool default timeout
{FLAME.Pool,
 name: MyApp.APIRunner,
 timeout: :timer.seconds(30),       # execution timeout
 boot_timeout: :timer.seconds(30),  # time to boot a new runner
 # ...
}

# Per-call timeout override
FLAME.call(MyApp.APIRunner, fn -> expensive_work() end, timeout: :timer.seconds(60))
```

Handle errors gracefully in your controllers:

```elixir
def show(conn, %{"id" => id}) do
  case FLAME.call(MyApp.APIRunner, fn -> MyApp.fetch_data(id) end) do
    {:ok, data} ->
      json(conn, %{data: data})

    {:error, reason} ->
      conn
      |> put_status(500)
      |> json(%{error: "Processing failed: #{inspect(reason)}"})
  end
rescue
  e ->
    conn
    |> put_status(503)
    |> json(%{error: "Service temporarily unavailable"})
end
```

## Summary

| Goal | Solution |
|------|----------|
| Offload heavy work from request handlers | `FLAME.call/3` in controllers |
| Fire-and-forget background processing | `FLAME.cast/3` in controllers |
| Start long-running workers from a request | `FLAME.place_child/3` |
| Distribute HTTP connections across servers | Use a load balancer (not FLAME) |
| Elastic compute that scales to zero | FLAME pools with `min: 0` |
| Different hardware for different endpoints | Multiple FLAME pools |

FLAME gives your Phoenix API elastic, lambda-like scaling without rewriting your
code. Your controllers, contexts, Repo calls, and PubSub all work identically on
the runner nodes because they boot your entire application. The key insight is
that you are not distributing the HTTP layer — you are distributing the *compute*
behind it.

## Working Example

See [`examples/flame_example/`](../examples/flame_example/) for a complete,
runnable Phoenix app that demonstrates all the patterns described in this guide.
