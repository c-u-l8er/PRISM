defmodule Prism.MCP.Machines.Server do
  @moduledoc """
  PRISM MCP v2 server — loop-phase machines.

  Exposes 6 tools instead of 47, organized around the closed evaluation loop:

      compose → interact → observe → reflect → diagnose  (+config)

  Each tool is a "machine" that dispatches to implementation functions via an
  `action` parameter. Paired with Graphonomous v2 (5 machines), a combined
  session sees 11 tools instead of 76.

  ## The dual-loop architecture

  When PRISM evaluates Graphonomous, the loops interlock:

      PRISM compose → interact → observe → reflect → diagnose
                         │
                         ▼
                Graphonomous retrieve → route → act → learn → consolidate

  See docs/DUAL_LOOP_MACHINES.md for the full design.
  """

  use Anubis.Server,
    name: "os-prism",
    version: "0.1.0",
    capabilities: [:tools]

  # The 5 loop-phase machines + 1 admin
  component(Prism.MCP.Machines.Compose)
  component(Prism.MCP.Machines.Interact)
  component(Prism.MCP.Machines.Observe)
  component(Prism.MCP.Machines.Reflect)
  component(Prism.MCP.Machines.Diagnose)
  component(Prism.MCP.Machines.Config)
end
