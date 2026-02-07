defmodule FlameExample.MixProject do
  use Mix.Project

  def project do
    [
      app: :flame_example,
      version: "0.1.0",
      elixir: "~> 1.14",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      aliases: aliases()
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {FlameExample.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix, "~> 1.7"},
      {:plug_cowboy, "~> 2.7"},
      {:jason, "~> 1.4"},
      {:telemetry, "~> 1.0"},
      {:flame, path: "../.."}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get"]
    ]
  end
end
