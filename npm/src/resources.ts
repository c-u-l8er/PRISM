/**
 * MCP resource registrations for os-prism.
 */
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Engine } from "./engine.js";
import type { Handle } from "./db.js";
import { MACHINE_LIST } from "./tools.js";

export interface ResourceContext {
  db: Handle;
  engine: Engine;
}

function jsonResource(uri: string, value: unknown) {
  return {
    contents: [
      {
        uri,
        mimeType: "application/json",
        text: JSON.stringify(value, null, 2),
      },
    ],
  };
}

export function registerResources(server: McpServer, ctx: ResourceContext): void {
  server.resource(
    "health",
    "prism://runtime/health",
    { mimeType: "application/json" },
    async (uri) => {
      const systemCount = (ctx.db.prepare("SELECT COUNT(*) AS c FROM systems").get() as {
        c: number;
      }).c;
      const runCount = (ctx.db.prepare("SELECT COUNT(*) AS c FROM runs").get() as {
        c: number;
      }).c;
      const toolCallCount = (
        ctx.db.prepare("SELECT COUNT(*) AS c FROM tool_calls").get() as { c: number }
      ).c;
      return jsonResource(uri.href, {
        status: "ok",
        package: "os-prism",
        version: "0.1.0",
        engine_available: ctx.engine.available,
        machines: Object.keys(MACHINE_LIST),
        action_count: Object.values(MACHINE_LIST).reduce((a, b) => a + b.length, 0),
        counts: {
          systems: systemCount,
          runs: runCount,
          tool_calls: toolCallCount,
        },
        timestamp: new Date().toISOString(),
      });
    },
  );

  server.resource(
    "registered-systems",
    "prism://systems/registered",
    { mimeType: "application/json" },
    async (uri) => {
      const rows = ctx.db
        .prepare(
          `SELECT id, name, manifest_uri, registered_at
           FROM systems ORDER BY registered_at DESC LIMIT 100`,
        )
        .all();
      return jsonResource(uri.href, { count: rows.length, systems: rows });
    },
  );

  server.resource(
    "recent-runs",
    "prism://runs/recent",
    { mimeType: "application/json" },
    async (uri) => {
      const rows = ctx.db
        .prepare(
          `SELECT id, system_id, scenario_id, status, started_at, ended_at
           FROM runs ORDER BY started_at DESC LIMIT 30`,
        )
        .all();
      return jsonResource(uri.href, { count: rows.length, runs: rows });
    },
  );
}
