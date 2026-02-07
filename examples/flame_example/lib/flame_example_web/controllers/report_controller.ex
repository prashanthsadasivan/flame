defmodule FlameExampleWeb.ReportController do
  @moduledoc """
  Demonstrates synchronous request distribution with `FLAME.call/3`.

  The full report computation runs on a FLAME runner node. The controller
  waits for the result and returns it as the JSON response. This keeps
  the parent node free to accept more HTTP connections while expensive
  work happens elsewhere.
  """
  use Phoenix.Controller, formats: [:json]

  require Logger

  # POST /api/reports
  def create(conn, params) do
    row_count = params["rows"] |> to_string() |> String.to_integer()
    report_name = params["name"] || "Untitled Report"

    # ------------------------------------------------------------------
    # FLAME.call/3 — this closure executes on a remote runner node.
    #
    # - `row_count` and `report_name` are captured in the closure and
    #   sent over Erlang distribution automatically.
    # - The runner boots a full copy of the app, so any module in your
    #   project is available (Repo, PubSub, contexts, etc.).
    # - The return value is sent back to this process on the parent node.
    # ------------------------------------------------------------------
    report =
      FLAME.call(FlameExample.RequestRunner, fn ->
        Logger.info("Generating report '#{report_name}' on node #{node()}")
        FlameExample.Reports.generate(report_name, row_count)
      end)

    conn
    |> put_status(:created)
    |> json(%{
      report: report,
      generated_on_node: report.node
    })
  end

  # GET /api/reports/:id
  def show(conn, %{"id" => id}) do
    # Another FLAME.call example — a simulated database lookup that
    # runs on the runner. In a real app with Ecto, the Repo is available
    # on the runner because it booted your full application.
    result =
      FLAME.call(FlameExample.RequestRunner, fn ->
        Logger.info("Fetching report #{id} on node #{node()}")
        FlameExample.Reports.fetch(id)
      end)

    case result do
      {:ok, report} ->
        json(conn, %{report: report})

      {:error, :not_found} ->
        conn
        |> put_status(:not_found)
        |> json(%{error: "Report not found"})
    end
  end
end
