/**
 * PRISM engine client.
 *
 * Spawns the Elixir PRISM engine as a child process and exchanges
 * line-delimited JSON-RPC messages over stdin/stdout. One request at a
 * time is sent; the client queues concurrent calls and resolves them in
 * FIFO order based on request id.
 *
 * If no engine is configured, the client operates in "stub" mode and
 * returns a structured `engine-unavailable` response for every call.
 * This keeps the MCP wrapper installable and discoverable even without
 * the Elixir runtime.
 */
import { spawn, type ChildProcessByStdio } from "node:child_process";
import type { Readable, Writable } from "node:stream";
import { existsSync } from "node:fs";
import { randomUUID } from "node:crypto";

export interface EngineOptions {
  enginePath: string | null;
  log: (level: string, msg: string) => void;
}

export interface EngineRequest {
  method: string;
  params: Record<string, unknown>;
}

export interface EngineResponse {
  ok: boolean;
  result?: unknown;
  error?: { code: string; message: string; details?: unknown };
  engine_available: boolean;
}

interface Pending {
  resolve: (value: EngineResponse) => void;
  reject: (err: Error) => void;
}

export class Engine {
  private readonly enginePath: string | null;
  private readonly log: (level: string, msg: string) => void;
  private proc: ChildProcessByStdio<Writable, Readable, null> | null = null;
  private stdoutBuffer = "";
  private readonly pending = new Map<string, Pending>();
  private started = false;

  constructor(opts: EngineOptions) {
    this.enginePath = opts.enginePath;
    this.log = opts.log;
  }

  get available(): boolean {
    return Boolean(this.enginePath) && existsSync(this.enginePath!);
  }

  async start(): Promise<void> {
    if (this.started) return;
    this.started = true;
    if (!this.available) {
      this.log(
        "warn",
        `PRISM engine not available (enginePath=${this.enginePath ?? "<unset>"}) — running in stub mode`,
      );
      return;
    }

    this.log("info", `spawning PRISM engine: ${this.enginePath}`);
    this.proc = spawn(this.enginePath!, [], {
      stdio: ["pipe", "pipe", "inherit"],
      env: process.env,
    });

    this.proc.stdout.setEncoding("utf8");
    this.proc.stdout.on("data", (chunk: string) => this.onStdout(chunk));
    this.proc.on("exit", (code) => {
      this.log("warn", `PRISM engine exited with code ${code}`);
      this.proc = null;
      for (const [, p] of this.pending) {
        p.reject(new Error(`PRISM engine exited (code=${code})`));
      }
      this.pending.clear();
    });
  }

  private onStdout(chunk: string): void {
    this.stdoutBuffer += chunk;
    let idx: number;
    while ((idx = this.stdoutBuffer.indexOf("\n")) >= 0) {
      const line = this.stdoutBuffer.slice(0, idx).trim();
      this.stdoutBuffer = this.stdoutBuffer.slice(idx + 1);
      if (!line) continue;
      try {
        const msg = JSON.parse(line) as { id: string } & EngineResponse;
        const p = this.pending.get(msg.id);
        if (!p) continue;
        this.pending.delete(msg.id);
        p.resolve({
          ok: msg.ok,
          result: msg.result,
          error: msg.error,
          engine_available: true,
        });
      } catch (err) {
        this.log("warn", `engine sent unparseable line: ${line}`);
      }
    }
  }

  async call(request: EngineRequest): Promise<EngineResponse> {
    await this.start();

    if (!this.proc) {
      return {
        ok: false,
        engine_available: false,
        error: {
          code: "engine-unavailable",
          message:
            "PRISM engine is not available. Set PRISM_ENGINE_PATH or --engine-path " +
            "to an executable speaking line-delimited JSON-RPC on stdin/stdout. " +
            "v0.1.0 of os-prism does not bundle the engine.",
          details: {
            method: request.method,
            enginePathConfigured: this.enginePath,
          },
        },
      };
    }

    const id = randomUUID();
    const line = JSON.stringify({ id, method: request.method, params: request.params }) + "\n";

    return new Promise<EngineResponse>((resolve, reject) => {
      this.pending.set(id, { resolve, reject });
      this.proc!.stdin.write(line, (err) => {
        if (err) {
          this.pending.delete(id);
          reject(err);
        }
      });
    });
  }

  async stop(): Promise<void> {
    if (this.proc) {
      this.proc.kill();
      this.proc = null;
    }
  }
}
