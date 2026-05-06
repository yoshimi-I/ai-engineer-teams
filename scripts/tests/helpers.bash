#!/usr/bin/env bash
# Shared helpers for BATS tests.
#
# Usage inside a .bats file:
#   load helpers
#   setup() { ts_setup; }
#   teardown() { ts_teardown; }
#
# ts_setup():
#   - Creates an isolated temp project rooted at $TS_ROOT
#   - Exports STATUS_DIR, CACHE_DIR, PANE_REGISTRY, common state files
#   - mkdir -p the required directories
#   - cd into $TS_ROOT so relative paths resolve inside the sandbox
#
# ts_teardown():
#   - rm -rf the sandbox
#
# Each test gets a fresh sandbox so there is no cross-test contamination.

ts_setup() {
  TS_ROOT="$(mktemp -d "${TMPDIR:-/tmp}/kiro-bats.XXXXXX")"
  export TS_ROOT

  # Resolve the real repo root so libraries can be sourced deterministically.
  # BATS_TEST_DIRNAME is scripts/tests; parent is scripts; its parent is repo.
  TS_REPO_ROOT="$(cd "${BATS_TEST_DIRNAME}/../.." && pwd)"
  export TS_REPO_ROOT
  export TS_LIB_DIR="${TS_REPO_ROOT}/scripts/lib"

  export STATUS_DIR="${TS_ROOT}/.agent-status"
  export CACHE_DIR="${STATUS_DIR}/.cache"
  export PANE_REGISTRY="${STATUS_DIR}/.panes"
  export POST_MERGE_STATE="${STATUS_DIR}/.last_post_merge_pr"
  export OPERATOR_REQUEST_FILE="${STATUS_DIR}/operator-request.json"
  export ORCH_STATUS_FILE="${STATUS_DIR}/orchestrator.json"
  export DECISION_FILE="${CACHE_DIR}/orchestrator_decision.json"
  export DEV_HEALTH_FILE="${STATUS_DIR}/dev-server-health.json"
  export AI_PLAN_FILE="${CACHE_DIR}/orchestrator_plan.json"

  # State vars referenced by lib scripts. Initialize to safe defaults so tests
  # don't trip set -u.
  ISSUES=0
  ISSUES_JSON="[]"
  READY_ISSUES=0
  PRS_JSON="[]"
  PRS_STATE_JSON="[]"
  CHANGES_REQ=0
  FIX_REVIEW_READY=0
  GH_USER=""
  LATEST_MERGED_PR=""
  HAS_MERGES=false
  LAST_PLAN_SOURCE="none"
  LAST_DECISION_SUMMARY=""
  LAST_DECISION_DETAIL=""
  LAST_DECISION_TS=""
  MAX_ALIVE=0
  MAX_IMPLEMENT=0
  MAX_FIX_REVIEW=3
  AUTO_DEV_SERVER=true
  AUTO_WATCH_MAIN=true
  AUTO_IMPROVE=false
  AUTO_UI_AUDIT=true
  INTEGRATION_BRANCH=develop
  STABLE_BRANCH=main

  export ISSUES ISSUES_JSON READY_ISSUES PRS_JSON PRS_STATE_JSON
  export CHANGES_REQ FIX_REVIEW_READY GH_USER LATEST_MERGED_PR HAS_MERGES
  export LAST_PLAN_SOURCE LAST_DECISION_SUMMARY LAST_DECISION_DETAIL LAST_DECISION_TS
  export MAX_ALIVE MAX_IMPLEMENT MAX_FIX_REVIEW
  export AUTO_DEV_SERVER AUTO_WATCH_MAIN AUTO_IMPROVE AUTO_UI_AUDIT
  export INTEGRATION_BRANCH STABLE_BRANCH

  mkdir -p "$STATUS_DIR" "$CACHE_DIR"
  touch "$PANE_REGISTRY"

  cd "$TS_ROOT" || exit 1
}

ts_teardown() {
  if [ -n "${TS_ROOT:-}" ] && [ -d "$TS_ROOT" ]; then
    rm -rf "$TS_ROOT"
  fi
}

# Load the common helpers (atomic_write, atomic_write_json, log, die).
ts_load_common() {
  # shellcheck source=../lib/common.sh
  source "${TS_LIB_DIR}/common.sh"
}

# Seed the pane registry with `name|role|pane|status` rows.
#   ts_seed_registry "dev-server|dev-server|terminal_1|alive" "impl-1|implement|terminal_2|alive"
ts_seed_registry() {
  : > "$PANE_REGISTRY"
  local row
  for row in "$@"; do
    printf '%s\n' "$row" >> "$PANE_REGISTRY"
  done
}
