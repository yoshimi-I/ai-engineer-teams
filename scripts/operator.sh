#!/usr/bin/env bash
# Interactive operator chat connected to the orchestrator through .agent-status/operator-request.json.
set -euo pipefail

STATUS_DIR=".agent-status"
PROMPT_FILE=".kiro/prompts/operator.md"

mkdir -p "$STATUS_DIR"

if [ ! -f "$PROMPT_FILE" ]; then
  echo "Missing $PROMPT_FILE" >&2
  exit 1
fi

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/runner.sh
source "${SCRIPT_DIR}/lib/runner.sh"

ai_run_interactive "$(cat "$PROMPT_FILE")"
