/**
 * os-prism MCP server wiring.
 *
 * Boots the high-level `McpServer`, attaches the Elixir engine client
 * (or stub if none is configured), and registers tools + resources over
 * stdio.
 */
import { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import type { Handle } from "./db.js";
import { Engine } from "./engine.js";
import { registerTools } from "./tools.js";
import { registerResources } from "./resources.js";

export interface ServerOptions {
  db: Handle;
  transport: "stdio" | "http";
  port: number;
  enginePath: string | null;
  log: (level: string, msg: string) => void;
}

export async function startServer(opts: ServerOptions): Promise<void> {
  const engine = new Engine({ enginePath: opts.enginePath, log: opts.log });
  await engine.start();

  const server = new McpServer({
    name: "os-prism",
    version: "0.1.0",
  });

  registerTools(server, { db: opts.db, engine, log: opts.log });
  registerResources(server, { db: opts.db, engine });

  if (opts.transport === "stdio") {
    const transport = new StdioServerTransport();
    await server.connect(transport);
    opts.log("info", "os-prism MCP server ready on stdio transport");
  } else {
    throw new Error(
      `HTTP transport is declared but not implemented in v0.1.0 — use --transport stdio`,
    );
  }
}
