#!/usr/bin/env bash
# Orchestrator: manages all agent panes, displays status, scales as needed
set -uo pipefail

export GIT_EDITOR=true
export EDITOR=true

PROJECT_CWD="$(pwd)"
STATUS_DIR=".agent-status"
CACHE_DIR="${STATUS_DIR}/.cache"
CACHE_TTL=25
PANE_REGISTRY="${STATUS_DIR}/.panes"
GH_REFRESH=60
TICK_INTERVAL="${ORCH_TICK_INTERVAL:-10}"
POST_MERGE_STATE="${STATUS_DIR}/.last_post_merge_pr"
PIPELINE_TAB_ID=""
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
LAST_DECISION_SUMMARY="booting"
LAST_DECISION_DETAIL="initializing"
LAST_DECISION_TS=""
LAST_PLAN_SOURCE="none"

mkdir -p "$STATUS_DIR" "$CACHE_DIR"
touch "$PANE_REGISTRY"

source scripts/lib/orchestrator-status.sh
source scripts/lib/github.sh
source scripts/lib/dev-server.sh
source scripts/lib/panes.sh
source scripts/lib/planner.sh
source scripts/lib/render.sh

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
  [ $((now - last_gh)) -ge $GH_REFRESH ] && refresh_github && last_gh=$now

  scale
  update_pane_status
  write_orchestrator_status "🟢 watching" "$LAST_DECISION_SUMMARY"
  render
done
