#!/usr/bin/env node
/**
 * os-prism CLI entrypoint.
 */
import yargs from "yargs";
import { hideBin } from "yargs/helpers";
import path from "node:path";
import os from "node:os";
import { mkdirSync } from "node:fs";
import { openDatabase } from "./db.js";
import { startServer } from "./server.js";

function expandHome(p: string): string {
  if (p.startsWith("~")) return path.join(os.homedir(), p.slice(1));
  return p;
}

async function main(): Promise<void> {
  const argv = await yargs(hideBin(process.argv))
    .scriptName("os-prism")
    .usage("$0 [options]")
    .option("db", {
      type: "string",
      describe: "SQLite projection database path",
      default: "~/.os-prism/benchmarks.db",
    })
    .option("transport", {
      type: "string",
      choices: ["stdio", "http"] as const,
      default: "stdio",
    })
    .option("port", {
      type: "number",
      describe: "HTTP port (ignored for stdio)",
      default: 4712,
    })
    .option("engine-path", {
      type: "string",
      describe:
        "Path to the PRISM Elixir engine executable (line-delimited JSON-RPC over stdio). " +
        "Defaults to $PRISM_ENGINE_PATH or <unset>.",
    })
    .option("log-level", {
      type: "string",
      choices: ["debug", "info", "warn", "error"] as const,
      default: "info",
    })
    .version()
    .help()
    .strict()
    .parseAsync();

  const dbPath = expandHome(argv.db);
  mkdirSync(path.dirname(dbPath), { recursive: true });

  const log = (level: string, msg: string) => {
    const order = ["debug", "info", "warn", "error"];
    if (order.indexOf(level) < order.indexOf(argv.logLevel)) return;
    process.stderr.write(`[os-prism ${level}] ${msg}\n`);
  };

  log("info", `opening projection database ${dbPath}`);
  const db = openDatabase(dbPath);

  const enginePath = argv.enginePath ?? process.env.PRISM_ENGINE_PATH ?? null;

  const transport = argv.transport as "stdio" | "http";
  log("info", `starting MCP server on ${transport} transport`);
  await startServer({
    db,
    transport,
    port: argv.port,
    enginePath,
    log,
  });
}

main().catch((err: unknown) => {
  const message = err instanceof Error ? err.stack ?? err.message : String(err);
  process.stderr.write(`[os-prism error] ${message}\n`);
  process.exit(1);
});
