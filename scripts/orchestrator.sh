#!/usr/bin/env bash
# Orchestrator: manages all agent panes, displays status, scales as needed
set -uo pipefail

export GIT_EDITOR=true
export EDITOR=true

PROJECT_CWD="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_DIR=".agent-status"
CACHE_DIR="${STATUS_DIR}/.cache"
CACHE_TTL=25
PANE_REGISTRY="${STATUS_DIR}/.panes"
GH_REFRESH="${ORCH_GH_REFRESH:-10}"
TICK_INTERVAL="${ORCH_TICK_INTERVAL:-10}"
POST_MERGE_STATE="${STATUS_DIR}/.last_post_merge_pr"
PIPELINE_TAB_ID=""
AGENTS_TAB_ID=""
MAX_ALIVE="${ORCH_MAX_ALIVE:-0}"
MAX_IMPLEMENT="${ORCH_MAX_IMPLEMENT:-0}"
AUTO_WATCH_MAIN="${ORCH_AUTO_WATCH_MAIN:-false}"
AUTO_IMPROVE="${ORCH_AUTO_IMPROVE:-false}"
AUTO_DEV_SERVER="${ORCH_AUTO_DEV_SERVER:-true}"
AI_ORCHESTRATION="${ORCH_AI:-true}"
AI_PLAN_PROMPT=".kiro/prompts/orchestrator-plan.md"
AI_PLAN_FILE="${CACHE_DIR}/orchestrator_plan.json"
DECISION_FILE="${CACHE_DIR}/orchestrator_decision.json"
ORCH_STATUS_FILE="${STATUS_DIR}/orchestrator.json"
DEV_HEALTH_FILE="${STATUS_DIR}/dev-server-health.json"
OPERATOR_REQUEST_FILE="${STATUS_DIR}/operator-request.json"
LAST_DECISION_SUMMARY="booting"
LAST_DECISION_DETAIL="initializing"
LAST_DECISION_TS=""
LAST_PLAN_SOURCE="none"

mkdir -p "$STATUS_DIR" "$CACHE_DIR"
touch "$PANE_REGISTRY"

for lib in \
  orchestrator-status.sh \
  github.sh \
  dev-server.sh \
  panes.sh \
  planner.sh \
  render.sh
do
  if [ ! -f "${SCRIPT_DIR}/lib/${lib}" ]; then
    echo "Missing ${SCRIPT_DIR}/lib/${lib}" >&2
    echo "Run ./scripts/update.sh once more to install the split orchestrator libraries." >&2
    exit 1
  fi
done

source "${SCRIPT_DIR}/lib/orchestrator-status.sh"
source "${SCRIPT_DIR}/lib/github.sh"
source "${SCRIPT_DIR}/lib/dev-server.sh"
source "${SCRIPT_DIR}/lib/panes.sh"
source "${SCRIPT_DIR}/lib/planner.sh"
source "${SCRIPT_DIR}/lib/render.sh"

ISSUES=0
READY_ISSUES=0
CHANGES_REQ=0
FIX_REVIEW_READY=0
GH_USER=""
HAS_MERGES=false
LATEST_MERGED_PR=""
last_gh=0

write_orchestrator_status "🚀 starting" "initializing orchestrator"
refresh_github

scale
render

while true; do
  sleep "$TICK_INTERVAL"

  now=$(date +%s)
  [ $((now - last_gh)) -ge "$GH_REFRESH" ] && refresh_github && last_gh=$now

  scale
  update_pane_status
  write_orchestrator_status "🟢 watching" "$LAST_DECISION_SUMMARY"
  render
done
