# PRISM — Protocol for Rating Iterative System Memory

**OpenSentience Specification OS-009-PRISM**

A self-improving continual learning evaluation engine for AI agent memory systems.

PRISM takes what looks like a single "memory benchmark score" and reveals the 9-dimensional CL spectrum underneath.

## What It Does

PRISM runs a three-phase loop:

1. **Generate** — An LLM produces benchmark questions from 9 CL category specs
2. **Execute** — Run questions against any memory system via MCP
3. **Judge** — An LLM scores answers, computes 9-dimensional CL scores, identifies gaps
4. **Loop** — Gap analysis feeds back into generation, making the benchmark harder each cycle

## The 9 CL Dimensions

| Dimension | Weight | What It Tests |
|-----------|--------|---------------|
| Stability | 20% | Retaining old knowledge when new arrives |
| Plasticity | 18% | Speed of learning new information |
| Knowledge Update | 15% | Detecting and resolving contradictions |
| Consolidation | 12% | Compressing episodes into insights |
| Temporal | 10% | Knowing when things happened |
| Transfer | 8% | Knowledge from domain A helping domain B |
| Epistemic Awareness | 7% | Knowing what you don't know |
| Intentional Forgetting | 5% | Deliberate pruning and GDPR erasure |
| Outcome Feedback | 5% | Retrieval improving from reward signals |

## Quick Start

```bash
# Install dependencies
mix deps.get

# Create database
mix ecto.setup

# Start the MCP server
mix run --no-halt

# Or add to Claude Code
claude mcp add prism -- mix run --no-halt
```

## MCP Tools (29)

Suite Management: `generate_suite`, `validate_suite`, `list_suites`, `get_suite`, `retire_question`, `import_external`

Execution: `run_eval`, `run_matrix`, `get_run_status`, `get_run_results`, `cancel_run`

Judging: `judge_run`, `judge_single`, `override_judgment`

Leaderboard: `get_leaderboard`, `get_leaderboard_history`, `compare_systems`, `get_dimension_leaders`

CL Meta-Loop: `analyze_gaps`, `propose_refinements`, `advance_cycle`, `get_cycle_history`, `detect_saturation`

Configuration: `set_cl_weights`, `register_system`, `list_systems`, `set_judge_model`, `set_generator_model`, `get_config`

## Deploy to Fly.io

```bash
fly launch --name prism-eval
fly postgres create --name prism-db
fly postgres attach prism-db
fly secrets set ANTHROPIC_API_KEY=sk-ant-...
fly secrets set OPENAI_API_KEY=sk-...
fly deploy
```

## Specification

Full spec: [OS-009-PRISM-SPECIFICATION.md](./OS-009-PRISM-SPECIFICATION.md)
Published at: [opensentience.org/prism](https://opensentience.org/prism)

## License

Apache 2.0
