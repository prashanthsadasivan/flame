defmodule FlameExampleWeb.JobController do
  @moduledoc """
  Demonstrates long-running background work with `FLAME.place_child/3`.

  A GenServer is started on a FLAME runner node and keeps running there
  independently. The runner stays alive as long as the child process is
  running (it counts against the runner's `max_concurrency`). The child
  can broadcast progress via PubSub since the full app is running on
  the runner.
  """
  use Phoenix.Controller, formats: [:json]

  require Logger

  # POST /api/jobs
  def create(conn, params) do
    job_id = generate_job_id()
    duration = params["duration_seconds"] |> to_string() |> String.to_integer()
    steps = params["steps"] |> to_string() |> String.to_integer()

    # ------------------------------------------------------------------
    # FLAME.place_child/3 — place a child spec on a FLAME runner.
    #
    # This starts a supervised GenServer on the remote node. The runner
    # will not idle-shutdown while this child is alive because it
    # occupies a concurrency slot. The child can do long-running work
    # (video transcoding, ML training, data pipelines) while reporting
    # progress back via PubSub.
    #
    # We pass `link: false` so the child survives even if this request
    # process terminates. The work will complete within the runner's
    # shutdown_timeout.
    # ------------------------------------------------------------------
    {:ok, pid} =
      FLAME.place_child(
        FlameExample.RequestRunner,
        {FlameExample.JobWorker, job_id: job_id, steps: steps, duration: duration},
        link: false
      )

    Logger.info("Started job #{job_id} on remote pid #{inspect(pid)} (node: #{node(pid)})")

    conn
    |> put_status(:accepted)
    |> json(%{
      job_id: job_id,
      status: "started",
      running_on_node: to_string(node(pid)),
      message: "Job placed on FLAME runner. Poll GET /api/jobs/#{job_id} for status."
    })
  end

  # GET /api/jobs/:id
  def show(conn, %{"id" => id}) do
    # Look up the job worker process via the Registry. Because this is
    # a distributed system, the worker lives on a remote FLAME node.
    # We use FLAME.call to query it from the same runner pool.
    status =
      FLAME.call(FlameExample.RequestRunner, fn ->
        case Registry.lookup(FlameExample.JobRegistry, id) do
          [{pid, _value}] ->
            FlameExample.JobWorker.get_status(pid)

          [] ->
            :not_found
        end
      end)

    case status do
      :not_found ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Job not found", job_id: id})

      status ->
        json(conn, %{job: status})
    end
  end

  defp generate_job_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
