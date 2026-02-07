defmodule FlameExample.Reports do
  @moduledoc """
  Simulated report generation context.

  In a real application this would query a database, crunch numbers,
  build PDFs, etc. Here we simulate CPU-bound work with a sleep and
  generate deterministic fake data so you can see the results.

  Every function in this module is designed to run inside a FLAME
  closure — no special adaptation is required. It's plain Elixir code.
  """

  require Logger

  @doc """
  Generates a report with the given name and number of rows.

  Simulates a CPU-intensive operation (e.g., aggregating millions of
  rows, rendering a PDF, running analytics queries).
  """
  def generate(name, row_count) when is_binary(name) and is_integer(row_count) do
    Logger.info("[Reports] Generating '#{name}' with #{row_count} rows on #{node()}")

    # Simulate CPU-bound work: 10ms per 100 rows, capped at 3 seconds.
    work_ms = min(div(row_count, 100) * 10, 3_000)
    Process.sleep(work_ms)

    rows =
      for i <- 1..min(row_count, 20) do
        %{
          row: i,
          value: :rand.uniform(10_000),
          label: "item_#{i}"
        }
      end

    %{
      id: generate_id(),
      name: name,
      row_count: row_count,
      rows: rows,
      total: Enum.reduce(rows, 0, fn r, acc -> acc + r.value end),
      generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
      node: to_string(node())
    }
  end

  @doc """
  Fetches a report by ID. Simulates a database lookup.
  """
  def fetch(id) when is_binary(id) do
    Logger.info("[Reports] Fetching report #{id} on #{node()}")

    # Simulate a database query
    Process.sleep(50)

    # For this example, we return a canned report for any ID that looks
    # valid, and :not_found otherwise.
    if String.length(id) > 2 do
      {:ok,
       %{
         id: id,
         name: "Cached Report",
         row_count: 100,
         rows: [%{row: 1, value: 42, label: "sample"}],
         total: 42,
         generated_at: DateTime.utc_now() |> DateTime.to_iso8601(),
         node: to_string(node())
       }}
    else
      {:error, :not_found}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.url_encode64(padding: false)
  end
end
