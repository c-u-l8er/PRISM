#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

LOG_DIR="${PRISM_LOG_DIR:-$HOME/.prism/logs}"
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/prism-mcp-$(date +%Y%m%d-%H%M%S).log"

DB_PATH="${PRISM_DB_PATH:-$HOME/.prism/prism.db}"
REQUEST_TIMEOUT="${PRISM_REQUEST_TIMEOUT:-180000}"
LOG_LEVEL="${PRISM_LOG_LEVEL:-error}"

# Keep stdout clean for MCP protocol frames.
# Route diagnostics to file + stderr only.
{
  echo "[wrapper] start $(date -Is)"
  echo "[wrapper] whoami=$(whoami)"
  echo "[wrapper] pwd=$(pwd)"
  echo "[wrapper] project_dir=$PROJECT_DIR"
  echo "[wrapper] db_path=$DB_PATH"
  echo "[wrapper] request_timeout=$REQUEST_TIMEOUT"
  echo "[wrapper] log_level=$LOG_LEVEL"
} >> "$LOG_FILE"

cd "$PROJECT_DIR"

exec 2> >(tee -a "$LOG_FILE" >&2)

mix run --no-start --no-compile -e "Prism.CLI.main([\"--db\",\"$DB_PATH\",\"--request-timeout\",\"$REQUEST_TIMEOUT\",\"--log-level\",\"$LOG_LEVEL\"])" -- "$@"
