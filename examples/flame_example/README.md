# FLAME Example: Phoenix API Request Distribution

A minimal Phoenix JSON API that demonstrates how to use [FLAME](https://github.com/phoenixframework/flame)
to distribute request processing across elastically scaled runner nodes.

## What This Demonstrates

| Endpoint              | FLAME Pattern       | Description                                              |
|-----------------------|---------------------|----------------------------------------------------------|
| `GET /api/health`     | *None (local)*      | Health check — runs on the parent node, no FLAME.        |
| `POST /api/reports`   | `FLAME.call/3`      | Synchronous — generates a report on a runner, returns it.|
| `GET /api/reports/:id`| `FLAME.call/3`      | Synchronous — fetches a report on a runner.              |
| `POST /api/webhooks`  | `FLAME.cast/3`      | Fire-and-forget — returns 202, processes in background.  |
| `POST /api/jobs`      | `FLAME.place_child/3`| Places a long-running GenServer on a runner.            |
| `GET /api/jobs/:id`   | `FLAME.call/3`      | Queries the running job worker for progress.             |

## Architecture

```
  HTTP Client
       │
       ▼
  Phoenix Endpoint  (parent node — serves HTTP)
       │
       ├── GET /api/health          → handled locally
       │
       ├── POST /api/reports        → FLAME.call(RequestRunner, fn -> ... end)
       │                                    │
       │                              ┌─────▼──────┐
       │                              │ FLAME Runner│  ← generates report, returns result
       │                              └────────────┘
       │
       ├── POST /api/webhooks       → FLAME.cast(BackgroundRunner, fn -> ... end)
       │                                    │
       │     (returns 202 immediately)┌─────▼──────┐
       │                              │ FLAME Runner│  ← processes webhook async
       │                              └────────────┘
       │
       └── POST /api/jobs           → FLAME.place_child(RequestRunner, {JobWorker, opts})
                                            │
                                      ┌─────▼──────┐
                                      │ FLAME Runner│  ← runs GenServer until job completes
                                      └────────────┘
```

## Running Locally

In development, FLAME uses the `LocalBackend` by default, which simply
runs your closures in the same node. This means you can develop and test
without any remote infrastructure.

```bash
cd examples/flame_example
mix setup
mix phx.server
```

The server starts on [http://localhost:4000](http://localhost:4000).

## Try the Endpoints

### Health Check

```bash
curl http://localhost:4000/api/health | jq
```

### Generate a Report (FLAME.call)

```bash
# Generate a report with 500 rows — the work runs on a FLAME runner
curl -X POST http://localhost:4000/api/reports \
  -H "Content-Type: application/json" \
  -d '{"name": "Q4 Sales", "rows": 500}' | jq
```

```bash
# Fetch a report by ID
curl http://localhost:4000/api/reports/abc123 | jq
```

### Process a Webhook (FLAME.cast)

```bash
# Returns 202 immediately — processing happens in background
curl -X POST http://localhost:4000/api/webhooks \
  -H "Content-Type: application/json" \
  -d '{"source": "stripe", "event": "invoice.paid", "payload": {"amount": 4999}}' | jq
```

### Start a Background Job (FLAME.place_child)

```bash
# Start a 5-step job that runs for ~10 seconds on a FLAME runner
curl -X POST http://localhost:4000/api/jobs \
  -H "Content-Type: application/json" \
  -d '{"steps": 5, "duration_seconds": 10}' | jq
```

```bash
# Check job progress (use the job_id from the response above)
curl http://localhost:4000/api/jobs/YOUR_JOB_ID | jq
```

## Deploying to Production (Fly.io)

In production, configure the Fly backend so that FLAME boots real
machines for each runner:

```elixir
# config/runtime.exs (already configured in this example)
config :flame, :backend, FLAME.FlyBackend
config :flame, FLAME.FlyBackend,
  token: System.fetch_env!("FLY_API_TOKEN"),
  env: %{
    "SECRET_KEY_BASE" => secret_key_base
  }
```

Key points:

- **FLAME runners don't serve HTTP.** The Phoenix endpoint is disabled on
  runner nodes via `server: !FLAME.Parent.get()` in `runtime.exs`.
- **Runners boot your entire app.** Every module, every dependency is
  available. Repo, PubSub, context modules — they all Just Work.
- **Runners scale to zero.** With `min: 0`, no machines run when there
  is no traffic. They boot on demand and shut down after the idle timeout.
- **Each pool can have different machine specs.** You could configure a
  GPU pool for ML inference and a CPU pool for report generation.

## Key Files

| File                                           | What It Shows                              |
|------------------------------------------------|--------------------------------------------|
| `lib/flame_example/application.ex`             | FLAME pool setup in supervision tree       |
| `lib/flame_example_web/controllers/report_controller.ex`  | `FLAME.call/3` for sync request handling   |
| `lib/flame_example_web/controllers/webhook_controller.ex` | `FLAME.cast/3` for fire-and-forget         |
| `lib/flame_example_web/controllers/job_controller.ex`     | `FLAME.place_child/3` for background work  |
| `lib/flame_example/job_worker.ex`              | GenServer that runs on a FLAME runner      |
| `config/runtime.exs`                           | Production backend + endpoint config       |
