# PRISM Live-Deployed Benchmark: Reconnaissance Report

**Claim:** "A benchmark submitted over the network to the deployed PRISM Fly.io machines returns a real judge judgment."

**Status:** `live_local` — with documented GAP to `live_deployed`.

**Date:** 2026-07-28T00:00:00Z (UTC)

---

## 1. Deployed Fly.io Application

| Field | Value |
|---|---|
| Fly.io app name | `prism-eval` |
| Region | `iad` (N. Virginia) |
| Endpoint (Fly proxy) | `https://prism-eval.fly.dev` |
| Custom domain (fly.toml `PHX_HOST`) | `prism.opensentience.org` |
| VM size | `shared-cpu-2x`, 1024 MB |
| Auto-stop/start | `auto_stop_machines = "stop"`, `auto_start_machines = true`, `min_machines_running = 1` |
| Persistent volume | `prism_data` → `/app/data` (SQLite WAL) |
| Release/deployment identity | v0.1.0 per `mix.exs`; STACK_COMPLETION.md records "2026-04-24 redeploy w/ stdio:// fix" |
| Image | Built from `PRISM/Dockerfile` (elixir:1.18-slim → debian:trixie-slim, `bin/prism start`) |
| Deployment command | `fly secrets set SECRET_KEY_BASE=$(mix phx.gen.secret) && fly deploy` |

## 2. HTTP Endpoints

| Path | Method | Purpose |
|---|---|---|
| `/` | GET | Marketing site (browser pipeline, Phoenix/HEEx) |
| `/api/health` | GET | Health check — returns `{"status":"ok","app":"prism","spec":"OS-009","version":"0.1.0","time":"..."}` |
| `/api/leaderboard` | GET | Leaderboard JSON (currently stub) |
| `/mcp` | POST | **MCP Streamable HTTP** — the benchmark submission interface (Anubis Server, CORS-enabled) |

## 3. MCP Benchmark Submission Interface

The `/mcp` endpoint serves 6 loop-phase machine tools via JSON-RPC 2.0 over Streamable HTTP:

| Machine | Actions | Role |
|---|---|---|
| `compose` | scenarios, validate, list, search, retire, import | Phase 1: build/manage scenarios |
| `interact` | run, run_sequence, run_matrix, status, transcript, cancel, byor_evaluate, byor_compare | Phase 2: execute benchmarks |
| `observe` | judge_transcript, judge_dimension, meta_judge, meta_judge_batch, override | Phase 3: judge results |
| `reflect` | analyze_gaps, evolve_scenarios, advance_cycle, calibrate_irt, cycle_history | Phase 4: meta-loop |
| `diagnose` | (various diagnostic actions) | Reporting |
| `config` | (get_config, set_cl_weights, register_system, list_systems) | Administration |

### Benchmark run path (end-to-end)

1. **Register a system**: `config(action: "register_system", name: "...", mcp_endpoint: "...", transport: "streamable_http")`
2. **Store scenarios**: `compose(action: "scenarios", scenario_ids: "[...]", repo_anchor_id: "...")`
3. **Run interaction**: `interact(action: "run", scenario_id: "...", system_id: "...", llm_backend: "...")`
   - Connects to the target memory system's MCP endpoint via `Prism.Simulator.McpClient` (HTTP POST JSON-RPC)
   - Executes scenario turns via `Prism.Simulator.Engine.interact/4`
   - Persists result as `Prism.Transcript` row
4. **Judge transcript**: `observe(action: "judge_transcript", transcript_id: "...", judge_model: "...", reason: "<JSON array of dimension judgments>")`
   - Stores `Prism.Judgment` rows per dimension
5. **Meta-judge**: `observe(action: "meta_judge", judgment_id: "...", meta_judge_model: "...")`
   - Must be different model family from L2 judge
   - Stores `Prism.MetaJudgment` row

### MCP Client Protocol (JSON-RPC 2.0)

```bash
# 1. Initialize session
curl -X POST https://prism-eval.fly.dev/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"benchmark-client","version":"0.1.0"}}}'

# Response includes Mcp-Session-Id header

# 2. Send initialized notification
curl -X POST https://prism-eval.fly.dev/mcp \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: <session-id>" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'

# 3. Call a tool (e.g., health/config check)
curl -X POST https://prism-eval.fly.dev/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: <session-id>" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"config","arguments":{"action":"get_config"}}}'
```

## 4. Real-Judge Configuration

| Config key | Default | Env var | Source |
|---|---|---|---|
| `judge_model` | `gpt-4o` | `JUDGE_MODEL` | `config/runtime.exs` line 41 |
| `generator_model` | `claude-sonnet-4-20250514` | `GENERATOR_MODEL` | `config/runtime.exs` line 40 |
| `runner_pool_size` | `4` | `RUNNER_POOL_SIZE` | `config/runtime.exs` line 42 |

**How judging works:** The `observe(judge_transcript)` machine action does **not** call an LLM internally. Instead:
- `Prism.Judge.DimensionWorker.judge/4` builds a structured rubric prompt and returns it as `status: "prompt_ready"`
- The calling agent (or human) executes the prompt against the configured `judge_model` externally
- The agent posts the judgment results back via `observe(action: "judge_transcript", reason: "<JSON array>")` or `observe(action: "judge_dimension", reason: "<JSON>")`
- Scores are persisted as `Prism.Judgment` rows

**Implication for live_deployed:** A "real judge judgment" requires:
1. Submitting an interaction transcript to the deployed PRISM `/mcp` endpoint
2. Either (a) the deployed PRISM calling an LLM API (which it does NOT currently do for judging — it returns prompts), or (b) an external agent/client running the prompt against `gpt-4o` (or another model) and posting the structured result back

## 5. Existing Live-Local Benchmark Command

The closest existing test is `test/prism/live_os011_test.exs` (tagged `@moduletag :live_os011`):

```bash
# Prerequisites: start Graphonomous locally
cd graphonomous && \
  GRAPHONOMOUS_TRANSPORT=http GRAPHONOMOUS_PORT=4201 \
  GRAPHONOMOUS_EMBEDDER_BACKEND=fallback \
  mix run --no-halt &

# Run the live test
cd PRISM && \
  mix test --include live_os011 test/prism/live_os011_test.exs
```

This test:
- Loads 10 OS-011 scenarios from `priv/fixtures/os011/scenarios.json`
- Stores them via `Compose.execute(action: "scenarios")`
- Registers Graphonomous as a system (endpoint: `http://127.0.0.1:4201/mcp` or `GRAPHONOMOUS_LIVE_URL`)
- Runs `Interact.execute(action: "run")` against live Graphonomous
- Asserts a `Prism.Transcript` row is persisted

**This is `live_local`**: it calls the Compose/Interact machine modules in-process (not over HTTP), and targets a local Graphonomous instance.

STACK_COMPLETION.md (§3.4) records: "PRISM → `graphonomous-mcp.fly.dev/mcp` — 3/3 `live_os011` (compose → register → interact → persist transcript)" as a verified smoke test.

## 6. GAP: What Blocks `live_deployed`

To move the claim from `live_local` to `live_deployed`, the following must all be true:

### GAP 1: Network submission to deployed PRISM
**Required:** A benchmark request sent over the public internet to `https://prism-eval.fly.dev/mcp` (or `https://prism.opensentience.org/mcp`), not to an in-process Elixir function call.
**Current state:** The existing `live_os011_test.exs` calls machine modules in-process. No test or script sends HTTP requests to the deployed PRISM endpoint.
**What would close it:** A curl/Req/client script that performs the MCP initialize handshake and `tools/call` against the deployed URL, capturing the HTTP response.

### GAP 2: Deployment reachability and currency
**Required:** Confirmation that `prism-eval.fly.dev` is currently responding and running the expected version.
**Current state:** STACK_COMPLETION.md says "2026-04-24 redeploy". Whether it is currently reachable (2026-07-28) is unknown — the machines use auto-stop and may need a wake-up request.
**What would close it:** `curl https://prism-eval.fly.dev/api/health` returning `{"status":"ok","version":"0.1.0",...}`, or `fly status -a prism-eval` confirming a running machine.

### GAP 3: Real judge judgment (not just transcript persistence)
**Required:** An L2 dimension judgment stored against a transcript produced by the deployed PRISM, where the judgment was produced by a real LLM (not a stub score).
**Current state:** The observe machine accepts agent-provided scores but does not call an LLM itself. The live_os011 test stops at transcript persistence (Phase 2); it never enters Phase 3 (observe/judge).
**What would close it:** After running `interact(run)` against the deployed endpoint, call `observe(judge_transcript)` with real LLM-evaluated dimension scores, then verify the `Prism.Judgment` rows exist in the deployed DB via `observe(judge_dimension)` or `diagnose`.

### GAP 4: Target memory system for the benchmark
**Required:** A memory system registered in the deployed PRISM's database with a reachable MCP endpoint.
**Current state:** The deployed Graphonomous MCP at `graphonomous-mcp.fly.dev/mcp` exists and was verified reachable as of 2026-04-24. Whether it is currently reachable is unknown.
**What would close it:** Confirming `https://graphonomous-mcp.fly.dev/health` responds, then registering it via `config(action: "register_system")` against the deployed PRISM.

### GAP 5: Scenario data in deployed DB
**Required:** Scenarios and a repo anchor in the deployed PRISM's SQLite database.
**Current state:** Unknown whether the deployed DB has any scenarios. The migration runs at boot, but scenario data must be inserted via the `compose` machine.
**What would close it:** Calling `compose(action: "scenarios")` against the deployed PRISM `/mcp` endpoint.

### Complete runnable sequence to close all gaps

```bash
# 0. Verify deployment is reachable
curl -s https://prism-eval.fly.dev/api/health | jq .

# 1. Initialize MCP session
SESSION=$(curl -s -D - https://prism-eval.fly.dev/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -d '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"live-deployed-bench","version":"0.1.0"}}}' \
  2>&1 | grep -i mcp-session-id | awk '{print $2}' | tr -d '\r')

# 2. Send initialized
curl -s https://prism-eval.fly.dev/mcp \
  -H "Content-Type: application/json" \
  -H "Mcp-Session-Id: $SESSION" \
  -d '{"jsonrpc":"2.0","method":"notifications/initialized"}'

# 3. Check config
curl -s https://prism-eval.fly.dev/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: $SESSION" \
  -d '{"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"config","arguments":{"action":"get_config"}}}' | jq .

# 4. Register Graphonomous as target system
curl -s https://prism-eval.fly.dev/mcp \
  -H "Content-Type: application/json" \
  -H "Accept: application/json, text/event-stream" \
  -H "Mcp-Session-Id: $SESSION" \
  -d '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"config","arguments":{"action":"register_system","name":"graphonomous-deployed","display_name":"Graphonomous (Fly.io)","mcp_endpoint":"https://graphonomous-mcp.fly.dev/mcp","transport":"streamable_http"}}}' | jq .

# 5. Store scenarios (requires repo anchor + scenario fixture)
# ... compose(action: "scenarios") with the os011 fixture data ...

# 6. Run interaction
# ... interact(action: "run", scenario_id: "...", system_id: "...", llm_backend: "agent") ...

# 7. Judge transcript (agent evaluates, posts structured scores)
# ... observe(action: "judge_transcript", transcript_id: "...", reason: "<JSON>") ...
```

**Prerequisites for the runnable sequence:**
- `fly` CLI authenticated with access to `prism-eval` app (for `fly status`)
- Network access to `prism-eval.fly.dev` (HTTPS, port 443)
- A running Graphonomous at `graphonomous-mcp.fly.dev` (or another target)
- An LLM API key (ANTHROPIC_API_KEY or OPENAI_API_KEY) for generating real judge scores
- The OS-011 scenario fixture data (`PRISM/priv/fixtures/os011/scenarios.json`)

## 7. Scenario and Benchmark Identity

| Item | Value |
|---|---|
| Benchmark name | OS-009 PRISM |
| Scenario fixture | `priv/fixtures/os011/scenarios.json` (10 OS-011 Embodiment Protocol scenarios) |
| CL dimensions exercised | plasticity, consolidation, transfer (verified in fixture metadata) |
| Existing live-local evidence | STACK_COMPLETION.md §3.4: "PRISM → `graphonomous-mcp.fly.dev/mcp` — 3/3 `live_os011`" |

---

## DOCTRINE:

**none** — this was reconnaissance work identifying the deployed application, benchmark interface, judge configuration, and prerequisites for a live-deployed benchmark run. No claim was moved on the evidence ladder. The five blocking GAPs are documented above; closing them requires network access to the deployed Fly.io machines and an LLM API key for real judging.
