defmodule Prism.MCP.Server do
  @moduledoc """
  MCP (Model Context Protocol) server exposing 30 tools for the PRISM evaluation engine.

  Transport: stdio (for Claude Code, Cursor, etc.) or SSE (for web clients).

  Tool categories:
  - Scenario Management (6 tools)
  - Interaction (6 tools)
  - Judging (5 tools)
  - Leaderboard (4 tools)
  - Meta-Loop & Calibration (5 tools)
  - Configuration (4 tools)
  """
  use GenServer
  require Logger

  alias Prism.Cycle.Manager

  @tools [
    # ── Scenario Management (6) ──
    %{
      name: "compose_scenarios",
      description:
        "Phase 1: Build scenarios from repo anchors + CL specs. Produces multi-session interaction scripts with embedded CL challenges and verifiable ground truth.",
      input_schema: %{
        type: "object",
        properties: %{
          repo_anchor_id: %{
            type: "string",
            description: "UUID of the repo anchor to compose from"
          },
          count: %{
            type: "integer",
            description: "Number of scenarios to generate (default 10)",
            default: 10
          },
          focus_dimensions: %{
            type: "array",
            items: %{type: "string"},
            description: "CL dimensions to emphasize"
          },
          focus_domains: %{
            type: "array",
            items: %{type: "string"},
            description: "Domains to weight toward"
          }
        }
      }
    },
    %{
      name: "validate_scenarios",
      description:
        "Run CL coverage validation on scenarios. Checks dimension and domain coverage, validates ground truth.",
      input_schema: %{
        type: "object",
        properties: %{
          scenario_ids: %{
            type: "array",
            items: %{type: "string"},
            description: "UUIDs of scenarios to validate"
          }
        },
        required: ["scenario_ids"]
      }
    },
    %{
      name: "list_scenarios",
      description: "List scenarios with filters for kind, domain, dimension, and difficulty.",
      input_schema: %{
        type: "object",
        properties: %{
          kind: %{type: "string", enum: ["anchor", "frontier"]},
          domain: %{
            type: "string",
            enum: [
              "code",
              "medical",
              "business",
              "personal",
              "research",
              "creative",
              "legal",
              "operations"
            ]
          },
          dimension: %{type: "string"},
          difficulty: %{type: "integer", minimum: 1, maximum: 5}
        }
      }
    },
    %{
      name: "get_scenario",
      description: "Full scenario details including sessions, CL challenges, and IRT parameters.",
      input_schema: %{
        type: "object",
        properties: %{scenario_id: %{type: "string", description: "UUID of the scenario"}},
        required: ["scenario_id"]
      }
    },
    %{
      name: "retire_scenario",
      description: "Retire a scenario with a reason. Anchor scenarios cannot be retired.",
      input_schema: %{
        type: "object",
        properties: %{
          scenario_id: %{type: "string"},
          reason: %{type: "string", enum: ["saturated", "ambiguous", "too_hard", "duplicate"]}
        },
        required: ["scenario_id", "reason"]
      }
    },
    %{
      name: "import_external",
      description:
        "Import scenarios from external benchmarks (BEAM, LongMemEval, etc.) with CL tagging and domain assignment.",
      input_schema: %{
        type: "object",
        properties: %{
          source: %{type: "string", description: "Benchmark name (e.g., 'BEAM', 'LongMemEval')"},
          file_path: %{type: "string", description: "Path to the benchmark data file"},
          domain: %{type: "string", description: "Domain to assign to imported scenarios"}
        },
        required: ["source", "file_path"]
      }
    },

    # ── Interaction (6) ──
    %{
      name: "run_interaction",
      description:
        "Execute one scenario against one memory system via the User Simulator. Produces a full interaction transcript.",
      input_schema: %{
        type: "object",
        properties: %{
          scenario_id: %{type: "string"},
          system_id: %{type: "string"},
          llm_backend: %{type: "string", description: "LLM model powering the memory system"}
        },
        required: ["scenario_id", "system_id", "llm_backend"]
      }
    },
    %{
      name: "run_sequence",
      description:
        "Execute a scenario sequence WITHOUT resetting memory between passes. Tests closed-loop learning.",
      input_schema: %{
        type: "object",
        properties: %{
          sequence_id: %{type: "string"},
          system_id: %{type: "string"},
          llm_backend: %{type: "string"}
        },
        required: ["sequence_id", "system_id", "llm_backend"]
      }
    },
    %{
      name: "run_matrix",
      description: "Full evaluation matrix: N systems × M models × all scenarios in a suite.",
      input_schema: %{
        type: "object",
        properties: %{
          suite_id: %{type: "string"},
          systems: %{
            type: "array",
            items: %{type: "string"},
            description: "System IDs to evaluate"
          },
          models: %{type: "array", items: %{type: "string"}, description: "LLM backends to test"}
        },
        required: ["suite_id", "systems", "models"]
      }
    },
    %{
      name: "get_run_status",
      description: "Check status of an in-progress run.",
      input_schema: %{
        type: "object",
        properties: %{run_id: %{type: "string"}},
        required: ["run_id"]
      }
    },
    %{
      name: "get_transcript",
      description: "Full interaction transcript with tool calls, retrieval contexts, and timing.",
      input_schema: %{
        type: "object",
        properties: %{transcript_id: %{type: "string"}},
        required: ["transcript_id"]
      }
    },
    %{
      name: "cancel_run",
      description: "Cancel an in-progress run.",
      input_schema: %{
        type: "object",
        properties: %{run_id: %{type: "string"}},
        required: ["run_id"]
      }
    },

    # ── Judging (5) ──
    %{
      name: "judge_transcript",
      description: "Layer 2: Judge all 9 CL dimensions for one transcript.",
      input_schema: %{
        type: "object",
        properties: %{
          transcript_id: %{type: "string"},
          judge_model: %{type: "string", description: "LLM model for judging"}
        },
        required: ["transcript_id"]
      }
    },
    %{
      name: "judge_dimension",
      description: "Layer 2: Judge one specific dimension for a transcript (debugging/manual).",
      input_schema: %{
        type: "object",
        properties: %{
          transcript_id: %{type: "string"},
          dimension: %{type: "string"},
          judge_model: %{type: "string"}
        },
        required: ["transcript_id", "dimension"]
      }
    },
    %{
      name: "meta_judge",
      description:
        "Layer 3: Meta-judge one L2 judgment. Evaluates consistency, evidence grounding, rubric compliance.",
      input_schema: %{
        type: "object",
        properties: %{
          judgment_id: %{type: "string"},
          meta_judge_model: %{
            type: "string",
            description: "MUST be different model family than L2 judge"
          }
        },
        required: ["judgment_id"]
      }
    },
    %{
      name: "meta_judge_batch",
      description: "Layer 3: Meta-judge all L2 judgments for a run.",
      input_schema: %{
        type: "object",
        properties: %{
          run_id: %{type: "string"},
          meta_judge_model: %{type: "string"}
        },
        required: ["run_id"]
      }
    },
    %{
      name: "override_judgment",
      description: "Human override of a judgment with audit trail.",
      input_schema: %{
        type: "object",
        properties: %{
          judgment_id: %{type: "string"},
          new_score: %{type: "number", minimum: 0, maximum: 1},
          reason: %{type: "string"}
        },
        required: ["judgment_id", "new_score", "reason"]
      }
    },

    # ── Leaderboard (4) ──
    %{
      name: "get_leaderboard",
      description:
        "Current rankings with optional domain filter. Shows 9 dimensions + loop closure rate.",
      input_schema: %{
        type: "object",
        properties: %{
          cycle: %{type: "integer"},
          dimension: %{type: "string", description: "Sort by this dimension"},
          domain: %{type: "string", description: "Filter by domain (nil = all domains)"},
          system: %{type: "string", description: "Filter to one system"},
          limit: %{type: "integer", default: 50}
        }
      }
    },
    %{
      name: "get_leaderboard_history",
      description: "Scores over time for trend analysis.",
      input_schema: %{
        type: "object",
        properties: %{
          system: %{type: "string"},
          from_cycle: %{type: "integer"},
          to_cycle: %{type: "integer"},
          domain: %{type: "string"}
        },
        required: ["system"]
      }
    },
    %{
      name: "compare_systems",
      description:
        "Head-to-head comparison across all 9 dimensions. Supports domain-specific comparison.",
      input_schema: %{
        type: "object",
        properties: %{
          system_a: %{type: "string"},
          system_b: %{type: "string"},
          cycle: %{type: "integer"},
          domain: %{type: "string"}
        },
        required: ["system_a", "system_b"]
      }
    },
    %{
      name: "get_dimension_leaders",
      description: "Top system per CL dimension. Supports domain filter.",
      input_schema: %{
        type: "object",
        properties: %{
          cycle: %{type: "integer"},
          domain: %{type: "string"}
        }
      }
    },

    # ── Meta-Loop & Calibration (5) ──
    %{
      name: "analyze_gaps",
      description:
        "Gap analysis: under-tested dimensions, saturated scenarios, low-variance dims, domain gaps.",
      input_schema: %{
        type: "object",
        properties: %{cycle: %{type: "integer"}}
      }
    },
    %{
      name: "evolve_scenarios",
      description:
        "Apply gap analysis: retire saturated scenarios, extend frontiers, fork for coverage, promote stable frontiers to anchor.",
      input_schema: %{
        type: "object",
        properties: %{
          cycle: %{type: "integer"},
          recommendations: %{type: "array", items: %{type: "object"}}
        }
      }
    },
    %{
      name: "advance_cycle",
      description:
        "Advance to next cycle: runs all 4 phases (Compose → Interact → Observe → Reflect).",
      input_schema: %{type: "object", properties: %{}}
    },
    %{
      name: "calibrate_irt",
      description:
        "Recalibrate IRT parameters (difficulty, discrimination) from accumulated cycle data.",
      input_schema: %{type: "object", properties: %{}}
    },
    %{
      name: "get_cycle_history",
      description:
        "Full history of cycles: gap analyses, scenario evolution, IRT recalibrations.",
      input_schema: %{type: "object", properties: %{}}
    },

    # ── Configuration (4) ──
    %{
      name: "set_cl_weights",
      description:
        "Update the 9-dimension weight vector. Must sum to 1.0. Requires governance approval during active cycles.",
      input_schema: %{
        type: "object",
        properties: %{
          weights: %{type: "object", description: "Map of dimension → weight (must sum to 1.0)"}
        },
        required: ["weights"]
      }
    },
    %{
      name: "register_system",
      description: "Register a memory system with its MCP endpoint for evaluation.",
      input_schema: %{
        type: "object",
        properties: %{
          name: %{type: "string"},
          display_name: %{type: "string"},
          mcp_endpoint: %{type: "string"},
          transport: %{type: "string", enum: ["stdio", "sse"]}
        },
        required: ["name", "mcp_endpoint", "transport"]
      }
    },
    %{
      name: "list_systems",
      description: "List all registered memory systems.",
      input_schema: %{type: "object", properties: %{}}
    },
    %{
      name: "get_config",
      description: "Current full PRISM configuration: weights, models, tier, costs.",
      input_schema: %{type: "object", properties: %{}}
    }
  ]

  # --- GenServer ---

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    transport = Keyword.get(opts, :transport, :stdio)
    Logger.info("[PRISM] MCP Server starting (transport: #{transport}, tools: #{length(@tools)})")
    {:ok, %{transport: transport, tools: @tools}}
  end

  # --- MCP Protocol ---

  @doc "Handle MCP tools/list request"
  def handle_tools_list do
    @tools
  end

  @doc "Handle MCP tool invocation"
  def handle_tool_call(name, args) do
    Logger.info("[PRISM] Tool call: #{name}")

    case dispatch(name, args) do
      {:ok, result} ->
        %{content: [%{type: "text", text: Jason.encode!(result)}]}

      {:error, reason} ->
        %{content: [%{type: "text", text: "Error: #{inspect(reason)}"}], isError: true}
    end
  end

  # --- Tool Dispatch ---

  defp dispatch("compose_scenarios", args) do
    opts = [
      count: Map.get(args, "count", 10),
      focus_dimensions: Map.get(args, "focus_dimensions"),
      focus_domains: Map.get(args, "focus_domains")
    ]

    case Map.get(args, "repo_anchor_id") do
      nil ->
        {:error, :repo_anchor_id_required}

      id ->
        case Prism.Repo.get(Prism.RepoAnchor, id) do
          nil -> {:error, :repo_anchor_not_found}
          anchor -> Prism.Scenario.Composer.compose(anchor, opts)
        end
    end
  end

  defp dispatch("validate_scenarios", args) do
    ids = Map.get(args, "scenario_ids", [])
    scenarios = Enum.map(ids, &Prism.Scenario.Library.get/1) |> Enum.filter(& &1)
    {:ok, Prism.Scenario.Validator.validate_coverage(scenarios)}
  end

  defp dispatch("list_scenarios", args) do
    filters = [
      kind: Map.get(args, "kind"),
      domain: Map.get(args, "domain"),
      dimension: Map.get(args, "dimension"),
      difficulty: Map.get(args, "difficulty")
    ]

    {:ok, Prism.Scenario.Library.list(filters)}
  end

  defp dispatch("get_scenario", %{"scenario_id" => id}) do
    case Prism.Scenario.Library.get(id) do
      nil -> {:error, :not_found}
      scenario -> {:ok, scenario}
    end
  end

  defp dispatch("retire_scenario", %{"scenario_id" => id, "reason" => reason}) do
    case Prism.Repo.get(Prism.Scenario, id) do
      nil ->
        {:error, :not_found}

      %{kind: "anchor"} ->
        {:error, :cannot_retire_anchor}

      scenario ->
        changeset = Prism.Scenario.retire_changeset(scenario, reason)

        case Prism.Repo.update(changeset) do
          {:ok, updated} ->
            Prism.Scenario.Library.reload()
            {:ok, %{retired: updated.id}}

          {:error, changeset} ->
            {:error, changeset}
        end
    end
  end

  defp dispatch("import_external", _args) do
    {:error, :not_implemented}
  end

  defp dispatch("run_interaction", %{
         "scenario_id" => sid,
         "system_id" => sysid,
         "llm_backend" => llm
       }) do
    scenario = Prism.Scenario.Library.get(sid)

    if scenario do
      Prism.Simulator.Engine.interact(scenario, %{}, sysid, llm)
    else
      {:error, :scenario_not_found}
    end
  end

  defp dispatch("run_sequence", %{
         "sequence_id" => seqid,
         "system_id" => sysid,
         "llm_backend" => llm
       }) do
    case Prism.Repo.get(Prism.Sequence, seqid) do
      nil -> {:error, :sequence_not_found}
      sequence -> Prism.Sequence.Runner.run(sequence, sysid, llm)
    end
  end

  defp dispatch("run_matrix", _args) do
    {:error, :not_implemented}
  end

  defp dispatch("get_run_status", %{"run_id" => id}) do
    case Prism.Repo.get(Prism.Run, id) do
      nil ->
        {:error, :not_found}

      run ->
        {:ok, %{status: run.status, started_at: run.started_at, completed_at: run.completed_at}}
    end
  end

  defp dispatch("get_transcript", %{"transcript_id" => id}) do
    case Prism.Repo.get(Prism.Transcript, id) do
      nil -> {:error, :not_found}
      transcript -> {:ok, transcript}
    end
  end

  defp dispatch("cancel_run", %{"run_id" => id}) do
    case Prism.Repo.get(Prism.Run, id) do
      nil ->
        {:error, :not_found}

      run ->
        changeset = Prism.Run.status_changeset(run, "cancelled")
        Prism.Repo.update(changeset)
    end
  end

  defp dispatch("judge_transcript", %{"transcript_id" => _id} = _args) do
    # TODO: Load transcript from DB, run DimensionWorker.judge_all
    {:error, :not_implemented}
  end

  defp dispatch("judge_dimension", %{"transcript_id" => _id, "dimension" => _dim} = args) do
    _model = Map.get(args, "judge_model", "claude-sonnet-4-20250514")
    {:error, :not_implemented}
  end

  defp dispatch("meta_judge", %{"judgment_id" => _id} = _args) do
    {:error, :not_implemented}
  end

  defp dispatch("meta_judge_batch", %{"run_id" => _id} = _args) do
    {:error, :not_implemented}
  end

  defp dispatch("override_judgment", %{
         "judgment_id" => _id,
         "new_score" => _score,
         "reason" => _reason
       }) do
    {:error, :not_implemented}
  end

  defp dispatch("get_leaderboard", args) do
    opts = [
      cycle: Map.get(args, "cycle"),
      dimension: Map.get(args, "dimension"),
      domain: Map.get(args, "domain"),
      limit: Map.get(args, "limit", 50)
    ]

    {:ok, Prism.Leaderboard.get(opts)}
  end

  defp dispatch("get_leaderboard_history", %{"system" => system} = args) do
    opts = [
      from_cycle: Map.get(args, "from_cycle"),
      to_cycle: Map.get(args, "to_cycle"),
      domain: Map.get(args, "domain")
    ]

    {:ok, Prism.Leaderboard.history(system, opts)}
  end

  defp dispatch("compare_systems", %{"system_a" => a, "system_b" => b} = args) do
    opts = [
      cycle: Map.get(args, "cycle"),
      domain: Map.get(args, "domain")
    ]

    {:ok, Prism.Leaderboard.compare(a, b, opts)}
  end

  defp dispatch("get_dimension_leaders", args) do
    opts = [
      cycle: Map.get(args, "cycle"),
      domain: Map.get(args, "domain")
    ]

    {:ok, Prism.Leaderboard.dimension_leaders(opts)}
  end

  defp dispatch("analyze_gaps", args) do
    cycle = Map.get(args, "cycle")
    Manager.analyze_gaps(cycle)
  end

  defp dispatch("evolve_scenarios", _args) do
    {:error, :not_implemented}
  end

  defp dispatch("advance_cycle", _args) do
    Manager.advance_cycle()
  end

  defp dispatch("calibrate_irt", _args) do
    Prism.IRT.Calibrator.recalibrate([])
    {:ok, Prism.IRT.Calibrator.summary()}
  end

  defp dispatch("get_cycle_history", _args) do
    {:ok, Manager.history()}
  end

  defp dispatch("set_cl_weights", %{"weights" => weights}) do
    atom_weights = Map.new(weights, fn {k, v} -> {String.to_existing_atom(k), v} end)

    case Prism.Benchmark.CLCategories.validate_weights(atom_weights) do
      :ok -> {:ok, %{weights: atom_weights, status: "updated"}}
      {:error, _} = err -> err
    end
  end

  defp dispatch("register_system", args) do
    changeset =
      Prism.System.changeset(%Prism.System{}, %{
        name: Map.get(args, "name"),
        display_name: Map.get(args, "display_name", Map.get(args, "name")),
        mcp_endpoint: Map.get(args, "mcp_endpoint"),
        transport: Map.get(args, "transport")
      })

    case Prism.Repo.insert(changeset) do
      {:ok, system} -> {:ok, %{id: system.id, name: system.name}}
      {:error, changeset} -> {:error, changeset}
    end
  end

  defp dispatch("list_systems", _args) do
    systems = Prism.Repo.all(Prism.System)
    {:ok, systems}
  end

  defp dispatch("get_config", _args) do
    state = Manager.state()

    {:ok,
     %{
       cycle: state.current_cycle,
       status: state.status,
       phase: state.phase,
       config: state.config,
       weights: Prism.Benchmark.CLCategories.default_weights(),
       domains: Prism.Domain.all_strings(),
       tool_count: length(@tools)
     }}
  end

  defp dispatch(unknown, _args) do
    {:error, {:unknown_tool, unknown}}
  end
end
