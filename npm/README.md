# os-prism

**OpenSentience OS-009 PRISM reference MCP server.**

One of four MCP servers in the [&] three-protocol stack:

| Package        | Role                                     | Install                                                          |
|----------------|------------------------------------------|------------------------------------------------------------------|
| `box-and-box`  | [&] Protocol validator / composer        | `npx -y box-and-box --db ~/.box-and-box/specs.db`                |
| `graphonomous` | Memory loop (5 machines)                 | `npx -y graphonomous --db ~/.graphonomous/knowledge.db`          |
| `os-prism`     | Diagnostic loop (**this**, 6 machines)  | `npx -y os-prism --db ~/.os-prism/benchmarks.db`                 |
| `os-pulse`     | PULSE manifest registry                  | `npx -y os-pulse --db ~/.os-pulse/manifests.db`                  |

## What os-prism does

- Exposes the **6 PRISM loop-phase machines** over stdio:
  `compose`, `interact`, `observe`, `reflect`, `diagnose`, `config`.
- Each machine accepts an `action` parameter and forwards the call to
  the Elixir PRISM engine via a simple JSON-RPC protocol on stdin/stdout.
- Persists a lightweight projection of registered systems, recent runs,
  and tool-call history in an embedded SQLite database for fast MCP
  resource responses.
- Designed to benchmark any PULSE-conforming memory system (Bring Your
  Own Reasoning / Bring Your Own Loop).

## v0.1.0 limitation: Elixir engine not bundled

The Elixir PRISM engine carries the IRT/Rasch calibration, three-layer
judging pipeline, and scenario evolution logic. Bundling it as a
cross-platform escript is deferred to v0.2.0. In v0.1.0:

- The TypeScript MCP wrapper installs and runs normally.
- All 6 machines are registered and discoverable.
- Tool calls return a structured `engine-unavailable` response unless
  you set `PRISM_ENGINE_PATH` (or `--engine-path`) to an executable that
  speaks line-delimited JSON-RPC on stdin/stdout.

See `docs/NPM_PACKAGE.md` for the full engine wire protocol.

## MCP tools (6 machines)

| Machine    | Actions                                                                 |
|------------|-------------------------------------------------------------------------|
| `compose`  | scenarios, validate, list, get, retire, byor_register, byor_discover     |
| `interact` | run, run_sequence, run_matrix, status, transcript, cancel, byor_evaluate, byor_compare |
| `observe`  | judge_transcript, judge_dimension, meta_judge, meta_judge_batch, override |
| `reflect`  | analyze_gaps, evolve, advance_cycle, calibrate_irt, cycle_history, byor_recommend, byor_infer_profile |
| `diagnose` | report, failure_patterns, retest, verify, regressions, suggest_fixes, leaderboard, leaderboard_history, compare_systems, dimension_leaders, fit_recommendation, compare_fit, task_profiles |
| `config`   | set_weights, register_system, list_systems, get_config, create_profile   |

Total: 45 actions.

## MCP resources

| URI                            | Returns                                 |
|--------------------------------|-----------------------------------------|
| `prism://runtime/health`       | Engine availability + counts.           |
| `prism://systems/registered`   | Registered memory systems.              |
| `prism://runs/recent`          | Recent benchmark runs.                  |

## Install

```bash
npx -y os-prism --db ~/.os-prism/benchmarks.db
```

Or in `.mcp.json`:

```jsonc
{
  "mcpServers": {
    "prism": {
      "command": "npx",
      "args": [
        "-y",
        "os-prism",
        "--db",
        "~/.os-prism/benchmarks.db"
      ],
      "env": {
        "PRISM_ENGINE_PATH": "/path/to/prism_engine"
      }
    }
  }
}
```

## Flags

| Flag                | Default                       |
|---------------------|-------------------------------|
| `--db <path>`       | `~/.os-prism/benchmarks.db`   |
| `--transport`       | `stdio` (only; HTTP planned)  |
| `--port`            | `4712` (ignored for stdio)    |
| `--engine-path`     | `$PRISM_ENGINE_PATH` or unset |
| `--log-level`       | `info`                        |

## Engine wire protocol

The wrapper spawns the engine as a child process and writes one JSON
object per line on its stdin:

```jsonc
{"id": "req-...", "method": "compose.list", "params": {"kind": "anchor"}}
```

and reads one JSON object per line on its stdout:

```jsonc
{"id": "req-...", "ok": true, "result": { ... }}
```

Any engine that implements this protocol and dispatches
`<machine>.<action>` calls onto the PRISM core modules can be used.

## Build from source

```bash
git clone https://github.com/c-u-l8er/AmpersandBoxDesign
cd AmpersandBoxDesign/PRISM/npm
npm install
npm run build
node bin/os-prism.js --help
```

## Spec

- [`docs/NPM_PACKAGE.md`](./docs/NPM_PACKAGE.md) — full package specification
- [OS-009 PRISM Specification](https://opensentience.org/docs/spec/OS-009-PRISM-SPECIFICATION.md)
- [`../lib/prism/mcp/machines/`](../lib/prism/mcp/machines/) — Elixir
  implementation of the 6 machines (the v0.1.0 wrapper delegates to these)

## License

Apache-2.0
