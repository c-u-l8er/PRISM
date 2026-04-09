# PRISM — Protocol for Rating Iterative System Memory

**OpenSentience Specification OS-009**

The first self-improving continual learning benchmark for AI agent memory systems.

## Legacy Benchmarks vs PRISM

| | Legacy (BEAM, LongMemEval, etc.) | PRISM |
|---|---|---|
| **Assessment** | Synthetic Q&A | Observational: agents interact naturally, judges observe transcripts |
| **Ground truth** | Author's expected answer | Git repos: the code IS the answer |
| **Learning test** | Single pass (store→retrieve→score) | Closed-loop: scenario sequences measure improvement over time |
| **Scoring** | One composite number | 9 CL dimensions × domain × loop closure rate |
| **Judging** | Single LLM judge | 3 layers: transcripts → dimension judges → meta-judges |
| **Evolution** | Static question bank | Self-improving: gap analysis evolves scenarios, IRT calibrates difficulty |
| **Domains** | Domain-agnostic | Tagged by domain for cross-domain comparison |

## The 9 CL Dimensions

| # | Dimension | Weight |
|---|-----------|--------|
| 1 | Stability (Anti-Forgetting) | 0.20 |
| 2 | Plasticity (New Acquisition) | 0.18 |
| 3 | Knowledge Update (Contradiction) | 0.15 |
| 4 | Temporal Reasoning | 0.12 |
| 5 | Consolidation (Abstraction) | 0.10 |
| 6 | Epistemic Awareness | 0.08 |
| 7 | Cross-Domain Transfer | 0.07 |
| 8 | Intentional Forgetting | 0.05 |
| 9 | Outcome Feedback | 0.05 |

## 4-Phase Evaluation Loop

```
Phase 1: Compose → Phase 2: Interact → Phase 3: Observe → Phase 4: Reflect
     ↑                                                          │
     └────────────────── Scenario Evolution ────────────────────┘
```

**Phase 1: Compose** — Build scenarios from git repo anchors with embedded CL challenges

**Phase 2: Interact** — User Simulator runs scenarios against memory systems via MCP

**Phase 3: Observe** — Three-layer judging: transcripts → L2 dimension judges → L3 meta-judges

**Phase 4: Reflect** — Gap analysis, IRT recalibration, scenario evolution

## Key Innovations

### Git-Grounded Anchors
Anchor scenarios use real git repositories as ground truth. Walk the commit history, ingest diffs, probe for understanding. The code IS the answer — checkout any commit to verify.

### Closed-Loop Testing
Scenario sequences run S1→S2→S3 without resetting memory. Measures whether the system *actually learns* from its own usage. Loop closure rate is a first-class leaderboard metric.

### Three-Layer Judging
- **Layer 1**: Raw interaction transcript (observable evidence)
- **Layer 2**: Per-dimension judges with structured rubrics
- **Layer 3**: Meta-judges that audit L2 (must use different model family)

### Domain Categories
Every scenario tagged by domain (code, medical, business, personal, research, creative, legal, operations). Enables "Who's best at medical CL?" comparisons.

## Quick Start

```bash
# Dependencies
mix deps.get

# Database
mix ecto.create
mix ecto.migrate

# Run
mix run --no-halt

# Or via MCP
echo '{"method":"tools/list"}' | mix run --no-halt
```

## Stack

- **Language**: Elixir 1.17+ / OTP 27
- **Database**: Postgres (via Ecto)
- **Protocol**: MCP with 30 tools (stdio/SSE)
- **LLM**: Anthropic Claude, OpenAI GPT-4o, Google Gemini
- **Deploy**: Fly.io

## Specification

Full spec: [OS-009-PRISM-SPECIFICATION.md](./OS-009-PRISM-SPECIFICATION.md)

## License

Apache 2.0
