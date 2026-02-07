defmodule FlameExample.JobWorker do
  @moduledoc """
  A GenServer that performs long-running work on a FLAME runner node.

  Started via `FLAME.place_child/3`, this process lives on the remote
  runner for its entire lifetime. The runner won't idle-shutdown while
  this worker is alive because it occupies a concurrency slot in the
  pool.

  The worker simulates a multi-step pipeline (like video transcoding,
  data migration, or ML training) and broadcasts progress via PubSub.
  """
  use GenServer

  require Logger

  # -- Public API ----------------------------------------------------------

  def start_link(opts) do
    job_id = Keyword.fetch!(opts, :job_id)
    GenServer.start_link(__MODULE__, opts, name: via(job_id))
  end

  def get_status(pid) when is_pid(pid) do
    GenServer.call(pid, :get_status)
  end

  def child_spec(opts) do
    job_id = Keyword.fetch!(opts, :job_id)

    %{
      id: {__MODULE__, job_id},
      start: {__MODULE__, :start_link, [opts]},
      restart: :temporary
    }
  end

  # -- Registry helper -----------------------------------------------------

  defp via(job_id), do: {:via, Registry, {FlameExample.JobRegistry, job_id}}

  # -- GenServer callbacks -------------------------------------------------

  @impl true
  def init(opts) do
    job_id = Keyword.fetch!(opts, :job_id)
    steps = Keyword.get(opts, :steps, 5)
    duration = Keyword.get(opts, :duration, 10)

    state = %{
      job_id: job_id,
      total_steps: steps,
      current_step: 0,
      status: :running,
      step_interval: div(duration * 1_000, max(steps, 1)),
      started_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      completed_at: nil,
      node: to_string(node())
    }

    Logger.info("[JobWorker] Job #{job_id} started on #{node()} — #{steps} steps, #{duration}s")

    # Kick off the first step
    Process.send_after(self(), :step, 0)

    {:ok, state}
  end

  @impl true
  def handle_info(:step, %{current_step: step, total_steps: total} = state) when step >= total do
    new_state = %{state | status: :completed, completed_at: DateTime.utc_now() |> DateTime.to_iso8601()}

    Logger.info("[JobWorker] Job #{state.job_id} completed all #{total} steps")
    broadcast_progress(new_state)

    # Stop the GenServer now that the job is done. This frees the
    # concurrency slot on the FLAME runner, allowing it to idle down.
    {:stop, :normal, new_state}
  end

  def handle_info(:step, state) do
    next_step = state.current_step + 1

    Logger.info(
      "[JobWorker] Job #{state.job_id} — step #{next_step}/#{state.total_steps} on #{node()}"
    )

    # Simulate doing work for this step
    Process.sleep(state.step_interval)

    new_state = %{state | current_step: next_step}
    broadcast_progress(new_state)

    # Schedule the next step
    Process.send_after(self(), :step, 0)

    {:noreply, new_state}
  end

  @impl true
  def handle_call(:get_status, _from, state) do
    reply = %{
      job_id: state.job_id,
      status: state.status,
      progress: "#{state.current_step}/#{state.total_steps}",
      percent: Float.round(state.current_step / max(state.total_steps, 1) * 100, 1),
      started_at: state.started_at,
      completed_at: state.completed_at,
      node: state.node
    }

    {:reply, reply, state}
  end

  # -- Helpers -------------------------------------------------------------

  defp broadcast_progress(state) do
    Phoenix.PubSub.broadcast(
      FlameExample.PubSub,
      "jobs:#{state.job_id}",
      {:job_progress, %{
        job_id: state.job_id,
        step: state.current_step,
        total: state.total_steps,
        status: state.status
      }}
    )
  end
end
