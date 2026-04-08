defmodule Prism.Application do
  @moduledoc """
  CL-Eval: Self-Improving Continual Learning Evaluation Engine.

  Supervision tree:
  - Repo (Postgres)
  - CycleManager (orchestrates the A→B→C loop)
  - RunnerPool (concurrent test execution)
  - MCPServer (exposes 29 tools via MCP)
  - Telemetry supervisor
  """
  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Database
      Prism.Repo,

      # Core engine
      {Prism.Cycle.Manager, []},
      {Prism.Runner.Pool, pool_size: pool_size()},

      # MCP Server (stdio transport)
      {Prism.MCP.Server, transport: :stdio},

      # Telemetry
      Prism.Telemetry
    ]

    opts = [strategy: :one_for_one, name: Prism.Supervisor]
    Supervisor.start_link(children, opts)
  end

  defp pool_size do
    System.get_env("RUNNER_POOL_SIZE", "4") |> String.to_integer()
  end
end
