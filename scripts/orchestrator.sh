#!/usr/bin/env bash
# Orchestrator: manages all agent panes, displays status, scales as needed.
#
# We intentionally use `set -uo pipefail` (no `-e`) because the orchestrator
# runs many best-effort `gh` / `jq` / `zellij` commands whose failure should
# NOT kill the loop — a transient GitHub API error must not stop scaling.
# Individual commands that must succeed already propagate errors via explicit
# return checks; commands that may fail are either wrapped with `|| true` or
# fall back via `gh_cached`.
#
# An ERR trap logs unexpected failures for debuggability without exiting.
set -uo pipefail

export GIT_EDITOR=true
export EDITOR=true

PROJECT_CWD="$(pwd)"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STATUS_DIR=".agent-status"
CACHE_DIR="${STATUS_DIR}/.cache"
CACHE_TTL=25
PANE_REGISTRY="${STATUS_DIR}/.panes"
INTEGRATION_BRANCH="${KIRO_INTEGRATION_BRANCH:-develop}"
STABLE_BRANCH="${KIRO_STABLE_BRANCH:-main}"
export KIRO_INTEGRATION_BRANCH="$INTEGRATION_BRANCH"
export KIRO_STABLE_BRANCH="$STABLE_BRANCH"
GH_REFRESH="${ORCH_GH_REFRESH:-10}"
TICK_INTERVAL="${ORCH_TICK_INTERVAL:-10}"
POST_MERGE_STATE="${STATUS_DIR}/.last_post_merge_pr"
PIPELINE_TAB_ID=""
AGENTS_TAB_ID=""
MAX_ALIVE="${ORCH_MAX_ALIVE:-0}"
MAX_IMPLEMENT="${ORCH_MAX_IMPLEMENT:-0}"
MAX_FIX_REVIEW="${ORCH_MAX_FIX_REVIEW:-3}"
AUTO_WATCH_MAIN="${ORCH_AUTO_WATCH_MAIN:-true}"
AUTO_IMPROVE="${ORCH_AUTO_IMPROVE:-false}"
AUTO_DEV_SERVER="${ORCH_AUTO_DEV_SERVER:-true}"
AUTO_UI_AUDIT="${ORCH_AUTO_UI_AUDIT:-true}"
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
[ -f "${STATUS_DIR}/user-attention.json" ] || echo '[]' > "${STATUS_DIR}/user-attention.json"

for lib in \
  common.sh \
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

# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/orchestrator-status.sh
source "${SCRIPT_DIR}/lib/orchestrator-status.sh"
# shellcheck source=lib/github.sh
source "${SCRIPT_DIR}/lib/github.sh"
# shellcheck source=lib/dev-server.sh
source "${SCRIPT_DIR}/lib/dev-server.sh"
# shellcheck source=lib/panes.sh
source "${SCRIPT_DIR}/lib/panes.sh"
# shellcheck source=lib/planner.sh
source "${SCRIPT_DIR}/lib/planner.sh"
# shellcheck source=lib/render.sh
source "${SCRIPT_DIR}/lib/render.sh"

# Log unexpected ERR events without exiting the loop. This is especially
# useful when a jq expression is broken or a zellij API call changes shape —
# we get a visible trace instead of a silent "nothing happens".
trap 'rc=$?; printf "[%s] ERROR orchestrator: cmd=\"%s\" src=%s:%s rc=%s\n" "$(date +%H:%M:%S)" "${BASH_COMMAND}" "${BASH_SOURCE[0]}" "${LINENO}" "$rc" >&2' ERR

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
