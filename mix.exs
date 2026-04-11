defmodule Prism.MixProject do
  use Mix.Project

  def project do
    [
      app: :prism,
      version: "0.1.0",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application do
    [
      extra_applications: [:logger, :runtime_tools],
      mod: {Prism.Application, []}
    ]
  end

  defp deps do
    [
      # Database — SQLite for local dev, Postgres for production (Supabase)
      {:ecto_sql, "~> 3.12"},
      {:ecto_sqlite3, "~> 0.17"},
      {:postgrex, ">= 0.0.0", optional: true},

      # HTTP client for LLM APIs
      {:req, "~> 0.5"},

      # JSON
      {:jason, "~> 1.4"},

      # Telemetry
      {:telemetry, "~> 1.2"},
      {:telemetry_metrics, "~> 1.0"},
      {:telemetry_poller, "~> 1.1"},

      # MCP server (vendored from graphonomous)
      {:anubis_mcp, path: "../graphonomous/vendor/anubis_mcp"},

      # UUID generation
      {:elixir_uuid, "~> 1.2"},

      # Phoenix web layer — landing page + leaderboard + future LiveView
      {:phoenix, "~> 1.7.14"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.0.0"},
      {:phoenix_live_reload, "~> 1.5", only: :dev},
      {:phoenix_pubsub, "~> 2.1"},
      {:bandit, "~> 1.5"},
      {:gettext, "~> 0.26"}
    ]
  end

  defp aliases do
    [
      setup: ["deps.get", "ecto.setup"],
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"]
    ]
  end
end
