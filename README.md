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

## Running locally

PRISM ships as a single Elixir/OTP app that runs three things side-by-side
in one supervision tree:

1. The **evaluation engine** (compose → interact → observe → reflect → diagnose)
2. The **MCP server** exposing six loop-phase machines over stdio
3. A **Phoenix 1.7 web layer** serving the marketing site at `/` and a JSON
   leaderboard at `/api/leaderboard`

### Prerequisites

- Elixir 1.17+ / Erlang/OTP 27
- SQLite (bundled via `ecto_sqlite3` — no extra install needed for dev)
- No Node / esbuild / Tailwind — CSS is hand-written in `priv/static/assets/app.css`

### First-time setup

```bash
cd PRISM
mix deps.get
mix ecto.create
mix ecto.migrate
```

The dev database lives at `~/.prism/prism_dev.db` (SQLite, WAL mode). Override
with `config/dev.exs` if you want it elsewhere.

### Start the Phoenix server (site + API + engine, all in one process)

```bash
mix phx.server
```

Then open:

- <http://localhost:4000/> — the marketing site
- <http://localhost:4000/api/leaderboard> — leaderboard JSON (currently a stub)
- <http://localhost:4000/api/health> — health check

Live reload is enabled in dev — edits to `lib/prism_web/**/*.{ex,heex}` and
`priv/static/**/*.css` trigger an automatic browser refresh.

### Start without the web layer (headless engine + MCP only)

```bash
mix run --no-halt
```

This boots the full supervision tree (including the Phoenix endpoint on 4000)
without attaching to the shell for HTTP serving. For a truly headless run
that skips the web layer entirely, set `PHX_SERVER=0` or comment out
`PrismWeb.Endpoint` in `lib/prism/application.ex`.

### Use as an MCP server from a Claude / Codex / Zed session

Add to your `.mcp.json`:

```jsonc
{
  "mcpServers": {
    "prism": { "command": "npx", "args": ["-y", "os-prism", "--db", "~/.os-prism/benchmarks.db"] }
  }
}
```

Or run directly against the checkout via stdio:

```bash
mix run --no-halt -e "Prism.MCP.Stdio.start()"
```

### Tests and format

```bash
mix test
mix format --check-formatted
```

### Production release (Fly.io)

The `Dockerfile` + `fly.toml` build a standalone release that serves the
site and the engine from the same VM. Before the first deploy, set the
Phoenix cookie secret as a Fly secret:

```bash
fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret)
fly deploy
```

The release listens on `PORT=4000` (see `fly.toml`) and is fronted by Fly's
HTTPS proxy at `https://prism-eval.fly.dev`.

## Stack

- **Language**: Elixir 1.17+ / OTP 27
- **Database**: Postgres (server mode via Ecto) · SQLite + sqlite-vec (local `os-prism` npm mode)
- **Protocol**: MCP exposed as **6 loop-phase machines** — `compose`, `interact`, `observe`, `reflect`, `diagnose`, `config` — over stdio (local) and SSE/Streamable HTTP (server). Each machine dispatches internally to 5–13 actions (down from 47 individual tools; see `docs/DUAL_LOOP_MACHINES.md`).
- **LLM**: Anthropic Claude, OpenAI GPT-4o, Google Gemini, OpenRouter
- **Deploy**: Fly.io (hosted) · `npx -y os-prism` (local)

## Four-Package MCP Stack

PRISM ships as one of four npm-distributed MCP servers that together form the [&] three-protocol stack. All four install identically with `npx -y <pkg> --db <path>` and carry their own embedded SQLite + sqlite-vec database:

| Package        | Role                                     | DB path                         |
|----------------|------------------------------------------|---------------------------------|
| `box-and-box`  | [&] Protocol validator / composer        | `~/.box-and-box/specs.db`       |
| `graphonomous` | Memory loop (5 machines)                 | `~/.graphonomous/knowledge.db`  |
| `os-prism`     | Diagnostic loop (6 machines, **this**)   | `~/.os-prism/benchmarks.db`     |
| `os-pulse`     | PULSE manifest registry (8 tools)        | `~/.os-pulse/manifests.db`      |

`.mcp.json` snippet to install all four:

```jsonc
{
  "mcpServers": {
    "ampersand":    { "command": "npx", "args": ["-y", "box-and-box",  "--db", "~/.box-and-box/specs.db"] },
    "graphonomous": { "command": "npx", "args": ["-y", "graphonomous", "--db", "~/.graphonomous/knowledge.db"] },
    "prism":        { "command": "npx", "args": ["-y", "os-prism",     "--db", "~/.os-prism/benchmarks.db"] },
    "pulse":        { "command": "npx", "args": ["-y", "os-pulse",     "--db", "~/.os-pulse/manifests.db"] }
  }
}
```

PRISM is **PULSE-evaluable**: once a memory system publishes a PULSE manifest, `os-prism compose` reads it directly to discover the `retrieve` boundary, the `learn` phase, and substrate URIs. No bespoke per-system integration is required — see `docs/DUAL_LOOP_MACHINES.md` § "Three-protocol stack at runtime."

## Specification

Full spec: [OS-009-PRISM-SPECIFICATION.md](./OS-009-PRISM-SPECIFICATION.md)

## License

Apache 2.0
