/**
 * Projection SQLite for os-prism.
 *
 * This is a small TS-side projection database that tracks registered
 * systems and recent runs so MCP resources can return quick snapshots
 * without round-tripping through the Elixir engine. The authoritative
 * benchmark state lives inside the engine's own SQLite file.
 */
import Database, { type Database as Db } from "better-sqlite3";

export type Handle = Db;

export function openDatabase(filePath: string): Handle {
  const db = new Database(filePath);
  db.pragma("journal_mode = WAL");
  db.pragma("foreign_keys = ON");
  db.exec(SCHEMA_SQL);
  return db;
}

const SCHEMA_SQL = `
CREATE TABLE IF NOT EXISTS systems (
  id             TEXT PRIMARY KEY,
  name           TEXT NOT NULL,
  manifest_uri   TEXT,
  registered_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS runs (
  id             TEXT PRIMARY KEY,
  system_id      TEXT NOT NULL,
  scenario_id    TEXT,
  status         TEXT NOT NULL,
  started_at     INTEGER NOT NULL,
  ended_at       INTEGER,
  transcript_uri TEXT,
  FOREIGN KEY (system_id) REFERENCES systems(id)
);

CREATE INDEX IF NOT EXISTS idx_runs_started_at ON runs(started_at);

CREATE TABLE IF NOT EXISTS tool_calls (
  id             INTEGER PRIMARY KEY AUTOINCREMENT,
  machine        TEXT NOT NULL,
  action         TEXT NOT NULL,
  status         TEXT NOT NULL,
  started_at     INTEGER NOT NULL,
  duration_ms    INTEGER,
  error_message  TEXT
);
CREATE INDEX IF NOT EXISTS idx_tool_calls_machine ON tool_calls(machine);
`;
