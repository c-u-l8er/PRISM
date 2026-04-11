# os-prism — NPM Package Specification

**Package**: `os-prism`
**Version**: `0.1.0` (initial)
**Language**: TypeScript (MCP wrapper) + Elixir (engine, vendored escript)
**License**: Apache-2.0
**Registry**: https://www.npmjs.com/package/os-prism
**Repository**: `AmpersandBoxDesign/PRISM` (monorepo subdir)

## Purpose

`os-prism` is the MCP server for OS-009 PRISM. It exposes the 6 PRISM
loop-phase machines (`compose`, `interact`, `observe`, `reflect`, `diagnose`,
`config`) over stdio and runs benchmarks against any PULSE-conforming memory
system. Unlike the Fly.io-hosted PRISM service, `os-prism` runs locally and
stores benchmark state in an embedded SQLite + sqlite-vec database.

`os-prism` wraps the existing Elixir PRISM engine via the same postinstall
escript pattern that `graphonomous` uses. The Elixir engine carries PRISM's
sophisticated IRT/Rasch calibration, three-layer judging pipeline, and
scenario evolution logic — porting those to JavaScript is out of scope for
v0.1 (the JS IRT ecosystem is thin; see `../../../memory/research`
for details).

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
      "args": ["-y", "os-prism", "--db", "~/.os-prism/benchmarks.db"]
    }
  }
}
```

`postinstall` fetches the platform-appropriate Elixir escript bundle
(darwin-x64, darwin-arm64, linux-x64, linux-arm64) from the GitHub release
assets attached to the matching `os-prism-vX.Y.Z` git tag, verifies the
SHA256, and installs it under `vendor/`. Offline installs can set
`PRISM_ESCRIPT_PATH` to skip the fetch.

## CLI Flags

| Flag                    | Default                       | Description                                          |
|-------------------------|-------------------------------|------------------------------------------------------|
| `--db <path>`           | `~/.os-prism/benchmarks.db`   | SQLite database path.                                |
| `--transport`           | `stdio`                       | `stdio` or `http`.                                   |
| `--port <n>`            | `4712`                        | HTTP port (ignored for stdio).                       |
| `--engine-path <path>`  | `./vendor/prism_engine`       | Path to the bundled Elixir escript.                  |
| `--llm-provider`        | `openrouter`                  | `openrouter`, `anthropic`, `openai`, `gemini`.       |
| `--llm-api-key-env`     | `OPENROUTER_API_KEY`          | Env var name to read the API key from.               |
| `--log-level`           | `info`                        | `debug`, `info`, `warn`, `error`.                    |
| `--version` / `--help`  | —                             | Print and exit.                                      |

## Dependencies

| Dependency                 | Version   | Why                                                     |
|----------------------------|-----------|---------------------------------------------------------|
| `@modelcontextprotocol/sdk`| `^1.29.0` | Stable v1.x MCP surface.                                |
| `better-sqlite3`           | `^12.8.0` | SQLite bindings (benchmark metadata).                   |
| `sqlite-vec`               | `^0.1.10` | Vector index over scenario embeddings.                  |
| `zod`                      | `^3.23.0` | Tool input schemas.                                     |
| `yargs`                    | `^17.7.0` | CLI parsing.                                            |
| `node-fetch`               | `^3.3.2`  | Escript bundle download (postinstall).                  |
| (Elixir runtime)           | via escript | `vendor/prism_engine` — the PRISM OTP app as an escript.|

The Elixir engine itself pulls: `ecto_sqlite3`, `exqlite`, `req`, `jason`,
`peri`, `nimble_options`. These live inside the escript bundle — they do
**not** appear in `package.json`.

## Wire Protocol (Node ⇄ Elixir)

The TS MCP server spawns the vendored escript as a child process and
communicates over line-delimited JSON on the escript's stdin/stdout. Each
MCP tool call is translated into a single JSON-RPC-style request:

```jsonc
// TS → escript
{ "id": "req-123", "method": "interact.run", "params": { "scenario_id": "s42" } }

// escript → TS
{ "id": "req-123", "ok": true, "result": { "run_id": "r_...", "transcript": "…" } }
```

The escript exposes exactly the same 6 machines + actions that the Elixir
PRISM application currently supports, so the TS wrapper is a thin pass-through
with zod input validation and MCP response shaping.

## SQLite Schema (TS-side)

The TS wrapper stores a small projection for fast MCP resource responses;
the authoritative benchmark state lives inside the escript's own SQLite
file (at the path passed via `--db`).

```sql
CREATE TABLE IF NOT EXISTS systems (
  id             TEXT PRIMARY KEY,                -- e.g. "graphonomous@0.4.0"
  name           TEXT NOT NULL,
  manifest_uri   TEXT,                            -- PULSE manifest URL or file path
  registered_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS runs (
  id             TEXT PRIMARY KEY,
  system_id      TEXT NOT NULL,
  scenario_id    TEXT NOT NULL,
  status         TEXT NOT NULL,                   -- queued | running | ok | error
  started_at     INTEGER NOT NULL,
  ended_at       INTEGER,
  transcript_uri TEXT,                            -- engine-side URI
  FOREIGN KEY (system_id) REFERENCES systems (id)
);
```

## MCP Tools (6 machines, 47 actions — delegated to Elixir)

| Machine    | Actions                                                                                             |
|------------|-----------------------------------------------------------------------------------------------------|
| `compose`  | `scenarios`, `validate`, `list`, `get`, `retire`, `import`, `byor_register`, `byor_discover`, `byor_generate` |
| `interact` | `run`, `run_sequence`, `run_matrix`, `status`, `transcript`, `cancel`, `byor_evaluate`, `byor_compare` |
| `observe`  | `judge_transcript`, `judge_dimension`, `meta_judge`, `meta_judge_batch`, `override`                 |
| `reflect`  | `analyze_gaps`, `evolve`, `advance_cycle`, `calibrate_irt`, `cycle_history`, `byor_recommend`, `byor_infer_profile` |
| `diagnose` | `report`, `failure_patterns`, `retest`, `verify`, `regressions`, `suggest_fixes`, `leaderboard`, `leaderboard_history`, `compare_systems`, `dimension_leaders`, `fit_recommendation`, `compare_fit`, `task_profiles` |
| `config`   | `set_weights`, `register_system`, `list_systems`, `get_config`, `create_profile`                    |

All 47 actions are already implemented in Elixir under
`PRISM/lib/prism/mcp/machines/`. The npm wrapper does not add or remove
actions; it only exposes them over the MCP SDK's stdio transport.

## MCP Resources

| URI                                | Returns                                            |
|------------------------------------|----------------------------------------------------|
| `prism://runtime/health`           | Engine health, pending run count, queue depth.    |
| `prism://systems/registered`       | Registered BYOR systems.                          |
| `prism://runs/recent`              | Recent benchmark runs.                            |
| `prism://leaderboard/{profile}`    | Leaderboard for a given task profile.             |
| `prism://scenarios/{id}`           | Scenario definition.                              |
| `prism://transcripts/{run_id}`     | Full transcript for a run.                        |

## Project Layout

```
PRISM/
├── package.json                    # "name": "os-prism"
├── tsconfig.json
├── bin/
│   └── os-prism.js
├── src/
│   ├── server.ts                   # MCP wiring
│   ├── db.ts                       # projection DB
│   ├── engine.ts                   # spawn + JSON-RPC over stdio
│   ├── tools/
│   │   ├── compose.ts
│   │   ├── interact.ts
│   │   ├── observe.ts
│   │   ├── reflect.ts
│   │   ├── diagnose.ts
│   │   └── config.ts
│   ├── resources/ …
│   └── cli.ts
├── scripts/
│   └── postinstall.js              # fetch vendor/prism_engine
└── lib/                            # existing Elixir PRISM app (escript source)
```

## Build and Publish

```bash
cd PRISM
# 1. Build the Elixir escript engine for each target platform
MIX_ENV=prod mix escript.build          # writes to ./prism_engine
# 2. Upload to GitHub Releases under tag os-prism-v0.1.0 (CI)
# 3. Build and publish the TS wrapper
npm install
npm run build
npm publish --access public
```

## Why os-prism ships third

1. Depends on `box-and-box` for reading `*.ampersand.json` spec graphs to
   understand what a system under test is composed of.
2. Depends on `os-pulse` to read the system-under-test's PULSE manifest and
   discover the `retrieve` and `learn` boundaries.
3. Requires the graphonomous-style postinstall escript pattern, which is
   the most complex install path of the four packages.
