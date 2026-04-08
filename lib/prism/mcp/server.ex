defmodule Prism.MCP.Server do
  @moduledoc """
  MCP (Model Context Protocol) server exposing 29 tools for the CL evaluation engine.

  Transport: stdio (for Claude Code, Cursor, etc.) or SSE (for web clients).

  Tool categories:
  - Suite Management (6 tools)
  - Execution (5 tools)
  - Judging (3 tools)
  - Leaderboard (4 tools)
  - CL Meta-Loop (5 tools)
  - Configuration (6 tools)
  """
  use GenServer
  require Logger

  alias Prism.Cycle.Manager

  @tools [
    # ── Suite Management ──
    %{
      name: "generate_suite",
      description: "Generate a new benchmark suite. LLM produces questions from CL category specs, validates coverage, stores in Postgres.",
      input_schema: %{
        type: "object",
        properties: %{
          target_questions: %{type: "integer", description: "Number of questions to generate (default 200)", default: 200},
          cycle: %{type: "integer", description: "Cycle number (auto-increments if omitted)"},
          focus_dimensions: %{type: "array", items: %{type: "string"}, description: "CL dimensions to emphasize (e.g. ['consolidation', 'transfer'])"}
        }
      }
    },
    %{
      name: "validate_suite",
      description: "Run CL coverage judge on a draft suite. Tags each question with CL categories, scores difficulty, rejects low-coverage items.",
      input_schema: %{
        type: "object",
        properties: %{
          suite_id: %{type: "string", description: "UUID of the suite to validate"}
        },
        required: ["suite_id"]
      }
    },
    %{
      name: "list_suites",
      description: "List all benchmark suites with status, coverage scores, and question counts.",
      input_schema: %{type: "object", properties: %{status: %{type: "string", enum: ["draft", "validated", "active", "retired"]}}}
    },
    %{
      name: "get_suite",
      description: "Get full details of a suite including all questions, CL tags, and coverage analysis.",
      input_schema: %{type: "object", properties: %{suite_id: %{type: "string"}}, required: ["suite_id"]}
    },
    %{
      name: "retire_question",
      description: "Mark a question as retired. Reasons: 'saturated' (all systems ace it), 'ambiguous', 'too_hard' (no system answers it).",
      input_schema: %{
        type: "object",
        properties: %{
          question_id: %{type: "string"},
          reason: %{type: "string", enum: ["saturated", "ambiguous", "too_hard", "duplicate"]}
        },
        required: ["question_id", "reason"]
      }
    },
    %{
      name: "import_external",
      description: "Import questions from external benchmarks (BEAM, LongMemEval, MemoryAgentBench) with automatic CL category tagging.",
      input_schema: %{
        type: "object",
        properties: %{
          source: %{type: "string", enum: ["beam", "longmemeval", "memoryagentbench", "memorybench", "custom"]},
          file_path: %{type: "string", description: "Path to benchmark data file"},
          max_questions: %{type: "integer", default: 100}
        },
        required: ["source"]
      }
    },

    # ── Execution ──
    %{
      name: "run_eval",
      description: "Execute a benchmark suite against a specific memory system via MCP. Records answers, retrieval context, and timing.",
      input_schema: %{
        type: "object",
        properties: %{
          suite_id: %{type: "string"},
          system: %{type: "string", description: "Registered memory system name"},
          llm_backend: %{type: "string", description: "LLM model for the memory system to use"}
        },
        required: ["suite_id", "system"]
      }
    },
    %{
      name: "run_matrix",
      description: "Run a suite against multiple systems × models. Full evaluation matrix.",
      input_schema: %{
        type: "object",
        properties: %{
          suite_id: %{type: "string"},
          systems: %{type: "array", items: %{type: "string"}},
          models: %{type: "array", items: %{type: "string"}}
        },
        required: ["suite_id", "systems"]
      }
    },
    %{
      name: "get_run_status",
      description: "Check the status of an in-progress evaluation run.",
      input_schema: %{type: "object", properties: %{run_id: %{type: "string"}}, required: ["run_id"]}
    },
    %{
      name: "get_run_results",
      description: "Get detailed results for a completed run including per-question scores and traces.",
      input_schema: %{type: "object", properties: %{run_id: %{type: "string"}}, required: ["run_id"]}
    },
    %{
      name: "cancel_run",
      description: "Cancel an in-progress evaluation run.",
      input_schema: %{type: "object", properties: %{run_id: %{type: "string"}}, required: ["run_id"]}
    },

    # ── Judging ──
    %{
      name: "judge_run",
      description: "LLM judges all answers in a run. Scores each answer 0-1 against the rubric, then aggregates into 9-dimensional CL scores.",
      input_schema: %{type: "object", properties: %{run_id: %{type: "string"}}, required: ["run_id"]}
    },
    %{
      name: "judge_single",
      description: "Judge a single answer. Useful for debugging or spot-checking.",
      input_schema: %{
        type: "object",
        properties: %{result_id: %{type: "string"}},
        required: ["result_id"]
      }
    },
    %{
      name: "override_judgment",
      description: "Human override of an LLM judgment. Records the override with reason for audit.",
      input_schema: %{
        type: "object",
        properties: %{
          result_id: %{type: "string"},
          new_score: %{type: "number", minimum: 0, maximum: 1},
          reason: %{type: "string"}
        },
        required: ["result_id", "new_score", "reason"]
      }
    },

    # ── Leaderboard ──
    %{
      name: "get_leaderboard",
      description: "Current leaderboard. Filterable by CL dimension, model, memory system, and cycle.",
      input_schema: %{
        type: "object",
        properties: %{
          cycle: %{type: "integer"},
          dimension: %{type: "string", description: "Filter by CL dimension"},
          system: %{type: "string"},
          limit: %{type: "integer", default: 20}
        }
      }
    },
    %{
      name: "get_leaderboard_history",
      description: "Leaderboard scores over time (per cycle) for trend analysis. See how systems improve.",
      input_schema: %{
        type: "object",
        properties: %{
          system: %{type: "string"},
          from_cycle: %{type: "integer"},
          to_cycle: %{type: "integer"}
        }
      }
    },
    %{
      name: "compare_systems",
      description: "Head-to-head comparison of two memory systems across all 9 CL dimensions.",
      input_schema: %{
        type: "object",
        properties: %{
          system_a: %{type: "string"},
          system_b: %{type: "string"},
          cycle: %{type: "integer"}
        },
        required: ["system_a", "system_b"]
      }
    },
    %{
      name: "get_dimension_leaders",
      description: "Who's best at each CL dimension? Returns the top system per dimension.",
      input_schema: %{type: "object", properties: %{cycle: %{type: "integer"}}}
    },

    # ── CL Meta-Loop ──
    %{
      name: "analyze_gaps",
      description: "Run gap analysis: which CL dims are under-tested? Which questions are saturated? Which are too hard?",
      input_schema: %{type: "object", properties: %{cycle: %{type: "integer"}}}
    },
    %{
      name: "propose_refinements",
      description: "LLM proposes refinements to CL category specs and question distribution based on gap analysis.",
      input_schema: %{type: "object", properties: %{cycle: %{type: "integer"}}}
    },
    %{
      name: "advance_cycle",
      description: "Move to the next cycle. Generates harder questions targeting weak dimensions, retires saturated ones.",
      input_schema: %{type: "object", properties: %{}}
    },
    %{
      name: "get_cycle_history",
      description: "Full history of cycles: feedback, refinements, improvements, and gap closure over time.",
      input_schema: %{type: "object", properties: %{}}
    },
    %{
      name: "detect_saturation",
      description: "Find questions that all systems ace (>0.95 across all runs). Candidates for retirement.",
      input_schema: %{type: "object", properties: %{threshold: %{type: "number", default: 0.95}}}
    },

    # ── Configuration ──
    %{
      name: "set_cl_weights",
      description: "Update the 9-dimensional CL weight vector. Must sum to 1.0.",
      input_schema: %{
        type: "object",
        properties: %{
          weights: %{type: "object", description: "Map of dimension_id → weight (0-1)"}
        },
        required: ["weights"]
      }
    },
    %{
      name: "register_system",
      description: "Register a new memory system for evaluation with its MCP endpoint.",
      input_schema: %{
        type: "object",
        properties: %{
          name: %{type: "string"},
          mcp_endpoint: %{type: "string", description: "MCP server URL or stdio command"},
          transport: %{type: "string", enum: ["stdio", "sse"]},
          version: %{type: "string"}
        },
        required: ["name", "mcp_endpoint"]
      }
    },
    %{
      name: "list_systems",
      description: "List all registered memory systems with their MCP endpoints and status.",
      input_schema: %{type: "object", properties: %{}}
    },
    %{
      name: "set_judge_model",
      description: "Configure which LLM model to use as the judge in Phase C.",
      input_schema: %{type: "object", properties: %{model: %{type: "string"}}, required: ["model"]}
    },
    %{
      name: "set_generator_model",
      description: "Configure which LLM model generates benchmark questions in Phase A.",
      input_schema: %{type: "object", properties: %{model: %{type: "string"}}, required: ["model"]}
    },
    %{
      name: "get_config",
      description: "Get current configuration: CL weights, models, registered systems, current cycle.",
      input_schema: %{type: "object", properties: %{}}
    }
  ]

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    transport = Keyword.get(opts, :transport, :stdio)
    Logger.info("[CL-Eval MCP] Server started (transport: #{transport}, tools: #{length(@tools)})")

    if transport == :stdio do
      # Start reading from stdin in a separate task
      Task.start_link(fn -> stdio_loop() end)
    end

    {:ok, %{transport: transport}}
  end

  @doc "Get all tool definitions for MCP tools/list response"
  def tools, do: @tools

  @doc "Handle a tool call from MCP"
  def handle_tool_call(name, arguments) do
    case name do
      "generate_suite" -> Manager.generate_suite(arguments)
      "run_eval" -> Manager.run_eval(arguments["suite_id"], arguments["system"], arguments)
      "run_matrix" -> Manager.run_matrix(arguments["suite_id"], arguments["systems"], arguments["models"])
      "judge_run" -> Manager.judge_run(arguments["run_id"])
      "analyze_gaps" -> Manager.analyze_gaps(arguments["cycle"])
      "advance_cycle" -> Manager.advance_cycle()
      "get_leaderboard" -> Prism.Leaderboard.get(arguments)
      "compare_systems" -> Prism.Leaderboard.compare(arguments["system_a"], arguments["system_b"])
      _ -> {:error, "Unknown tool: #{name}"}
    end
  end

  # ── MCP Protocol (stdio) ───────────────────────────────────────────

  defp stdio_loop do
    case IO.read(:stdio, :line) do
      :eof -> :ok
      {:error, _} -> :ok
      line ->
        line
        |> String.trim()
        |> process_mcp_message()

        stdio_loop()
    end
  end

  defp process_mcp_message(""), do: :ok
  defp process_mcp_message(json) do
    case Jason.decode(json) do
      {:ok, %{"jsonrpc" => "2.0", "method" => method, "id" => id} = msg} ->
        result = handle_mcp_method(method, msg)
        response = %{"jsonrpc" => "2.0", "id" => id, "result" => result}
        IO.write(:stdio, Jason.encode!(response) <> "\n")

      {:ok, %{"jsonrpc" => "2.0", "method" => method} = msg} ->
        # Notification (no id)
        handle_mcp_method(method, msg)

      {:error, _} ->
        Logger.warning("[MCP] Invalid JSON: #{json}")
    end
  end

  defp handle_mcp_method("initialize", _msg) do
    %{
      "protocolVersion" => "2024-11-05",
      "capabilities" => %{"tools" => %{"listChanged" => true}},
      "serverInfo" => %{
        "name" => "cl-eval",
        "version" => "0.1.0"
      }
    }
  end

  defp handle_mcp_method("tools/list", _msg) do
    %{"tools" => Enum.map(@tools, fn tool ->
      %{
        "name" => tool.name,
        "description" => tool.description,
        "inputSchema" => tool.input_schema
      }
    end)}
  end

  defp handle_mcp_method("tools/call", %{"params" => %{"name" => name, "arguments" => args}}) do
    case handle_tool_call(name, args) do
      {:ok, result} ->
        %{"content" => [%{"type" => "text", "text" => Jason.encode!(result)}]}

      {:error, reason} ->
        %{"content" => [%{"type" => "text", "text" => "Error: #{reason}"}], "isError" => true}
    end
  end

  defp handle_mcp_method(method, _msg) do
    Logger.warning("[MCP] Unknown method: #{method}")
    %{"error" => %{"code" => -32601, "message" => "Method not found"}}
  end
end
