/**
 * MCP tool registrations for os-prism.
 *
 * Exposes the 6 PRISM loop-phase machines as MCP tools. Each tool is
 * registered with a zod schema whose shape mirrors the corresponding
 * Elixir `Prism.MCP.Machines.*.schema` block; calls are forwarded to
 * the engine via JSON-RPC.
 */
import { z, type ZodRawShape } from "zod";
import type { McpServer } from "@modelcontextprotocol/sdk/server/mcp.js";
import type { Engine } from "./engine.js";
import type { Handle } from "./db.js";

export interface ToolContext {
  db: Handle;
  engine: Engine;
  log: (level: string, msg: string) => void;
}

const MACHINES: Record<string, readonly string[]> = {
  compose: [
    "scenarios",
    "validate",
    "list",
    "get",
    "retire",
    "byor_register",
    "byor_discover",
  ],
  interact: [
    "run",
    "run_sequence",
    "run_matrix",
    "status",
    "transcript",
    "cancel",
    "byor_evaluate",
    "byor_compare",
  ],
  observe: [
    "judge_transcript",
    "judge_dimension",
    "meta_judge",
    "meta_judge_batch",
    "override",
  ],
  reflect: [
    "analyze_gaps",
    "evolve",
    "advance_cycle",
    "calibrate_irt",
    "cycle_history",
    "byor_recommend",
    "byor_infer_profile",
  ],
  diagnose: [
    "report",
    "failure_patterns",
    "retest",
    "verify",
    "regressions",
    "suggest_fixes",
    "leaderboard",
    "leaderboard_history",
    "compare_systems",
    "dimension_leaders",
    "fit_recommendation",
    "compare_fit",
    "task_profiles",
  ],
  config: [
    "set_weights",
    "register_system",
    "list_systems",
    "get_config",
    "create_profile",
  ],
};

const MACHINE_DESCRIPTIONS: Record<string, string> = {
  compose:
    "PRISM Loop Phase 1 — COMPOSE. Scenario management: store agent-composed scenarios, validate CL coverage, list/get/retire, and manage BYOR repo anchors.",
  interact:
    "PRISM Loop Phase 2 — INTERACT. Execute scenarios against registered memory systems, run sequences/matrices, stream transcripts, and evaluate BYOR systems.",
  observe:
    "PRISM Loop Phase 3 — OBSERVE. Three-layer judging pipeline: judge transcripts and CL dimensions, run meta-judgments and batches, override scores.",
  reflect:
    "PRISM Loop Phase 4 — REFLECT. Analyze gaps, evolve scenarios, advance evaluation cycles, recalibrate IRT parameters, and recommend systems for task profiles.",
  diagnose:
    "PRISM Loop Phase 5 — DIAGNOSE. Produce diagnostic reports, failure pattern analyses, leaderboards, regressions, fix suggestions, and task-fit recommendations.",
  config:
    "PRISM Loop Phase 6 — CONFIG. Configure CL dimension weights, register memory systems, list systems, get config, and create task profiles.",
};

// Full input schema mirroring the Elixir Peri schemas. A permissive bag:
// every known field from every machine, all optional. The engine does the
// strict per-action validation — the wrapper's job is to forward.
function buildMachineSchema(machine: string): ZodRawShape {
  const actions = MACHINES[machine];
  return {
    action: z
      .enum(actions as [string, ...string[]])
      .describe(`${machine} action: ${actions.join(" | ")}`),
    // Generic params bag — forwarded verbatim. Avoids drift with the
    // Elixir engine's schema while still giving the LLM enough hinting
    // via the tool description to pass sensible values.
    params: z
      .record(z.string(), z.unknown())
      .optional()
      .describe(
        "Action-specific parameters. See the PRISM OS-009 spec for per-action fields.",
      ),
  };
}

function json(content: unknown): { content: Array<{ type: "text"; text: string }> } {
  return {
    content: [{ type: "text", text: JSON.stringify(content, null, 2) }],
  };
}

export function registerTools(server: McpServer, ctx: ToolContext): void {
  for (const machine of Object.keys(MACHINES)) {
    server.registerTool(
      machine,
      {
        title: `PRISM ${machine}`,
        description: MACHINE_DESCRIPTIONS[machine],
        inputSchema: buildMachineSchema(machine),
      },
      async (input) => {
        const started = Date.now();
        const res = await ctx.engine.call({
          method: `${machine}.${input.action}`,
          params: (input.params as Record<string, unknown>) ?? {},
        });
        const duration = Date.now() - started;

        ctx.db
          .prepare(
            `INSERT INTO tool_calls (machine, action, status, started_at, duration_ms, error_message)
             VALUES (?, ?, ?, ?, ?, ?)`,
          )
          .run(
            machine,
            input.action,
            res.ok ? "ok" : "error",
            started,
            duration,
            res.error?.message ?? null,
          );

        return json({
          machine,
          action: input.action,
          engine_available: res.engine_available,
          ...(res.ok ? { ok: true, result: res.result } : { ok: false, error: res.error }),
        });
      },
    );
  }
}

export const MACHINE_LIST = MACHINES;
