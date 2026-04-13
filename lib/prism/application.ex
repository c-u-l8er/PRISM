defmodule Prism.Application do
  @moduledoc """
  PRISM: Self-Improving Continual Learning Evaluation Engine.

  Supervision tree:
  - Repo (SQLite in dev, Postgres in prod)
  - Phoenix.PubSub + PrismWeb.Endpoint (landing page + leaderboard API)
  - Scenario.Library (ETS-cached scenarios + IRT params)
  - Simulator.Supervisor (concurrent interaction sessions)
  - Judge.Supervisor (concurrent judging tasks)
  - IRT.Calibrator (parameter estimation)
  - Cycle.Manager (4-phase loop orchestrator)
  - Telemetry
  """
  use Application

  @impl true
  def start(_type, _args) do
    # In-memory store for task profiles (no DB table yet)
    :ets.new(:prism_task_profiles, [:named_table, :set, :public])

    # Run Ecto migrations at boot in releases (prod). In dev/test, migrations
    # are run via `mix ecto.migrate` as usual.
    if System.get_env("RELEASE_NAME") do
      migrate_on_boot()
    end

    children = [
      # MCP Registry (required by Anubis.Server.Supervisor)
      Anubis.Server.Registry,

      # Database
      Prism.Repo,

      # Phoenix web layer
      {Phoenix.PubSub, name: Prism.PubSub},
      PrismWeb.Endpoint,

      # MCP server over Streamable HTTP (served via Phoenix at /mcp)
      %{
        id: :prism_mcp_http,
        start:
          {Anubis.Server.Supervisor, :start_link,
           [
             Prism.MCP.Machines.Server,
             [transport: {:streamable_http, start: true}, request_timeout: 120_000]
           ]}
      },

      # Scenario library (ETS cache)
      Prism.Scenario.Library,

      # Concurrent execution supervisors
      Prism.Simulator.Supervisor,
      Prism.Judge.Supervisor,

      # IRT calibration
      Prism.IRT.Calibrator,

      # Core engine (4-phase loop)
      {Prism.Cycle.Manager, []},

      # Telemetry
      Prism.Telemetry
    ]

    opts = [strategy: :one_for_one, name: Prism.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration whenever the
  # application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    PrismWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp migrate_on_boot do
    path = Application.app_dir(:prism, "priv/repo/migrations")

    {:ok, _, _} =
      Ecto.Migrator.with_repo(Prism.Repo, fn repo ->
        Ecto.Migrator.run(repo, path, :up, all: true)
      end)
  end
end
