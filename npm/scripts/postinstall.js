#!/usr/bin/env node
/**
 * os-prism postinstall.
 *
 * In v0.1.0 this is a friendly no-op: the Elixir PRISM engine is not yet
 * packaged as a downloadable escript bundle. The TypeScript MCP wrapper
 * will still install and run, but individual tool calls return a
 * structured "engine-unavailable" response until an engine is attached.
 *
 * To attach an engine, set `PRISM_ENGINE_PATH` to an executable that
 * speaks line-delimited JSON-RPC on stdin/stdout (see docs/NPM_PACKAGE.md
 * wire protocol section).
 */

// Honor CI silence — only log if installed in a real user context.
if (process.env.CI || process.env.OS_PRISM_QUIET === "1") {
  process.exit(0);
}

process.stdout.write(
  [
    "",
    "[os-prism] installed v0.1.0 (MCP wrapper).",
    "[os-prism] The Elixir engine is not bundled in v0.1.0.",
    "[os-prism] Tools will return engine-unavailable responses until you set",
    "[os-prism]   PRISM_ENGINE_PATH=/path/to/prism_engine",
    "[os-prism] or use a future os-prism release with bundled engines.",
    "",
  ].join("\n"),
);
