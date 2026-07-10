#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2034
# Tests for scripts/lib/planner.sh pure functions.
#
# We isolate the pure JSON/shape functions from the ones that call out to
# zellij / kiro-cli. The ones we test here are the ones that govern the
# orchestrator's core decisions:
#   - valid_role                → gates which roles may be launched
#   - ready_issue_numbers_json  → drives "which issue to implement next"
#   - review_pr_numbers_json    → drives "which PR to merge next"
#   - fix_review_pr_numbers_json→ drives "which PR needs fix-review"
#   - extract_json_object       → parses AI planner output

load helpers

setup() {
  ts_setup
  ts_load_common
  # planner.sh depends on a few panes.sh helpers (active_implement_issues_json,
  # pane_name_active, role_active, etc.), so we source panes.sh first.
  # shellcheck source=../lib/panes.sh
  source "${TS_LIB_DIR}/panes.sh"
  # shellcheck source=../lib/planner.sh
  source "${TS_LIB_DIR}/planner.sh"
}

teardown() {
  ts_teardown
}

# ── valid_role ──────────────────────────────────────────────────────────────

@test "valid_role accepts all known roles" {
  for role in dev-server implement review fix-review e2e e2e-bug-hunt ui-audit watch-main improve feature-discovery create-issue; do
    run valid_role "$role"
    [ "$status" -eq 0 ] || { echo "role $role should be valid"; return 1; }
  done
}

@test "valid_role rejects unknown roles" {
  run valid_role "hack-the-planet"
  [ "$status" -ne 0 ]
  run valid_role ""
  [ "$status" -ne 0 ]
  run valid_role "implement-1"
  [ "$status" -ne 0 ]
}

# ── extract_json_object ─────────────────────────────────────────────────────

@test "extract_json_object returns JSON inside a fenced code block" {
  local input='Some preamble.
```json
{"actions": [{"role": "implement"}]}
```
Trailing text.'
  run bash -c 'source "$1"; source "$2"; source "$3"; printf "%s" "$4" | extract_json_object' \
    _ "${TS_LIB_DIR}/common.sh" "${TS_LIB_DIR}/panes.sh" "${TS_LIB_DIR}/planner.sh" "$input"
  [ "$status" -eq 0 ]
  run jq -r '.actions[0].role' <<< "$output"
  [ "$output" = "implement" ]
}

@test "extract_json_object returns raw JSON when input is pure JSON" {
  local input='{"actions":[{"role":"review"}]}'
  run bash -c 'source "$1"; source "$2"; source "$3"; printf "%s" "$4" | extract_json_object' \
    _ "${TS_LIB_DIR}/common.sh" "${TS_LIB_DIR}/panes.sh" "${TS_LIB_DIR}/planner.sh" "$input"
  [ "$status" -eq 0 ]
  run jq -r '.actions[0].role' <<< "$output"
  [ "$output" = "review" ]
}

@test "extract_json_object tolerates JSON with surrounding prose" {
  local input='Here is the plan:
{
  "actions": [{"role": "fix-review", "name": "fix-review-pr-7"}]
}
Let me know if that is OK.'
  run bash -c 'source "$1"; source "$2"; source "$3"; printf "%s" "$4" | extract_json_object' \
    _ "${TS_LIB_DIR}/common.sh" "${TS_LIB_DIR}/panes.sh" "${TS_LIB_DIR}/planner.sh" "$input"
  [ "$status" -eq 0 ]
  # Should parse as JSON.
  run jq -r '.actions[0].name' <<< "$output"
  [ "$output" = "fix-review-pr-7" ]
}

# ── ready_issue_numbers_json ────────────────────────────────────────────────

@test "ready_issue_numbers_json returns unassigned, unblocked issues when GH_USER is set" {
  ISSUES_JSON=$(cat <<'JSON'
[
  {"number": 10, "assignees": [], "labels": [], "body": ""},
  {"number": 11, "assignees": [], "labels": [{"name":"bug"}], "body": ""},
  {"number": 12, "assignees": [{"login":"alice"}], "labels": [], "body": ""}
]
JSON
)
  export ISSUES_JSON
  # When GH_USER is a real login, issues assigned to other people are excluded.
  GH_USER="bob"
  run ready_issue_numbers_json
  [ "$status" -eq 0 ]
  # Should include 10 and 11 (unassigned).
  # Should exclude 12 (assigned to alice, not bob).
  run bash -c "jq 'sort' <<<'$output'"
  [ "$output" = "[
  10,
  11
]" ]
}

@test "ready_issue_numbers_json restricts to unassigned issues when GH_USER cannot be resolved" {
  # When gh auth is broken or the API rate-limits us, GH_USER is empty. In
  # that degraded state the safer semantics is to only pick up unassigned
  # issues so we do not accidentally collide with another agent's in-flight
  # issue. The old "starvation-avoidance" behaviour that returned every open
  # issue broke the assignee-based mutex between parallel implement panes.
  ISSUES_JSON=$(cat <<'JSON'
[
  {"number": 10, "assignees": [], "labels": [], "body": ""},
  {"number": 12, "assignees": [{"login":"alice"}], "labels": [], "body": ""}
]
JSON
)
  export ISSUES_JSON
  GH_USER=""
  run ready_issue_numbers_json
  [ "$status" -eq 0 ]
  run bash -c "jq 'sort' <<<'$output'"
  [ "$output" = "[
  10
]" ]
}

@test "ready_issue_numbers_json excludes issues with blocked label" {
  ISSUES_JSON=$(cat <<'JSON'
[
  {"number": 20, "assignees": [], "labels": [{"name":"blocked"}], "body": ""},
  {"number": 21, "assignees": [], "labels": [], "body": ""}
]
JSON
)
  export ISSUES_JSON
  GH_USER=""
  run ready_issue_numbers_json
  [ "$status" -eq 0 ]
  run jq 'sort' <<< "$output"
  [ "$output" = "[
  21
]" ]
}

@test "ready_issue_numbers_json excludes issues waiting on open dependency" {
  # Issue 31 depends on 30, and 30 is still open, so 31 is NOT ready.
  # Issue 33 depends on 99, which is NOT in the open list, so 33 IS ready.
  ISSUES_JSON=$(cat <<'JSON'
[
  {"number": 30, "assignees": [], "labels": [], "body": ""},
  {"number": 31, "assignees": [], "labels": [], "body": "depends-on: #30"},
  {"number": 33, "assignees": [], "labels": [], "body": "depends-on: #99"}
]
JSON
)
  export ISSUES_JSON
  GH_USER=""
  run ready_issue_numbers_json
  [ "$status" -eq 0 ]
  run jq 'sort' <<< "$output"
  [ "$output" = "[
  30,
  33
]" ]
}

@test "ready_issue_numbers_json honours the new blocked-by: #N (type) syntax" {
  # Same dependency semantics, new body format. Issue 41 is blocked by 40
  # which is still open, so only 40 is ready. Issue 43 is blocked by 999 which
  # is not in the open list, so 43 IS ready. The (type) annotation is just a
  # human comment and must not break the scan.
  ISSUES_JSON=$(cat <<'JSON'
[
  {"number": 40, "assignees": [], "labels": [], "body": ""},
  {"number": 41, "assignees": [], "labels": [], "body": "blocked-by: #40 (contract)"},
  {"number": 43, "assignees": [], "labels": [], "body": "blocked-by: #999 (impl)"}
]
JSON
)
  export ISSUES_JSON
  GH_USER=""
  run ready_issue_numbers_json
  [ "$status" -eq 0 ]
  run jq 'sort' <<< "$output"
  [ "$output" = "[
  40,
  43
]" ]
}

@test "ready_issue_numbers_json honours multiple dependency lines (mixed syntax)" {
  # Issue 51 has two deps: one blocked-by (open) + one depends-on (closed).
  # The open one blocks it. Issue 52 has both deps closed so it is ready.
  ISSUES_JSON=$(cat <<'JSON'
[
  {"number": 50, "assignees": [], "labels": [], "body": ""},
  {"number": 51, "assignees": [], "labels": [], "body": "blocked-by: #50 (data)\ndepends-on: #999"},
  {"number": 52, "assignees": [], "labels": [], "body": "blocked-by: #9998 (infra)\ndepends-on: #9999"}
]
JSON
)
  export ISSUES_JSON
  GH_USER=""
  run ready_issue_numbers_json
  [ "$status" -eq 0 ]
  run jq 'sort' <<< "$output"
  [ "$output" = "[
  50,
  52
]" ]
}

@test "ready_issue_numbers_json includes issues self-assigned to current user (recovery case)" {
  ISSUES_JSON=$(cat <<'JSON'
[
  {"number": 40, "assignees": [{"login":"me"}], "labels": [], "body": ""},
  {"number": 41, "assignees": [{"login":"other"}], "labels": [], "body": ""}
]
JSON
)
  export ISSUES_JSON
  GH_USER="me"
  run ready_issue_numbers_json
  [ "$status" -eq 0 ]
  run jq 'sort' <<< "$output"
  [ "$output" = "[
  40
]" ]
}

@test "ready_issue_numbers_json excludes issues already owned by an active implement pane" {
  ISSUES_JSON=$(cat <<'JSON'
[
  {"number": 50, "assignees": [], "labels": [], "body": ""},
  {"number": 51, "assignees": [], "labels": [], "body": ""}
]
JSON
)
  export ISSUES_JSON
  GH_USER=""
  # Seed registry: implement-issue-50 is already running.
  ts_seed_registry "implement-issue-50|implement|terminal_1|alive"
  run ready_issue_numbers_json
  [ "$status" -eq 0 ]
  run jq 'sort' <<< "$output"
  [ "$output" = "[
  51
]" ]
}

# ── review_pr_numbers_json ──────────────────────────────────────────────────

@test "review_pr_numbers_json returns only approved_ready and approved_pending PRs" {
  PRS_STATE_JSON=$(cat <<'JSON'
[
  {"number": 100, "pipelineState": "review_pending"},
  {"number": 101, "pipelineState": "approved_ready"},
  {"number": 102, "pipelineState": "approved_pending"},
  {"number": 103, "pipelineState": "changes_requested"},
  {"number": 104, "pipelineState": "conflict"}
]
JSON
)
  export PRS_STATE_JSON
  run review_pr_numbers_json
  [ "$status" -eq 0 ]
  run jq 'sort' <<< "$output"
  [ "$output" = "[
  101,
  102
]" ]
}

@test "review_pr_numbers_json skips PRs already assigned to an active review pane" {
  PRS_STATE_JSON=$(cat <<'JSON'
[
  {"number": 200, "pipelineState": "approved_ready"},
  {"number": 201, "pipelineState": "approved_ready"}
]
JSON
)
  export PRS_STATE_JSON
  ts_seed_registry "review-pr-200|review|terminal_1|alive"
  run review_pr_numbers_json
  [ "$status" -eq 0 ]
  run jq 'sort' <<< "$output"
  [ "$output" = "[
  201
]" ]
}

# ── fix_review_pr_numbers_json ──────────────────────────────────────────────

@test "fix_review_pr_numbers_json returns PRs in changes_requested/conflict/approved_checks_failed/merge_blocked" {
  PRS_STATE_JSON=$(cat <<'JSON'
[
  {"number": 300, "pipelineState": "approved_ready"},
  {"number": 301, "pipelineState": "changes_requested"},
  {"number": 302, "pipelineState": "conflict"},
  {"number": 303, "pipelineState": "approved_checks_failed"},
  {"number": 304, "pipelineState": "merge_blocked"},
  {"number": 305, "pipelineState": "review_pending"}
]
JSON
)
  export PRS_STATE_JSON
  run fix_review_pr_numbers_json
  [ "$status" -eq 0 ]
  run jq 'sort' <<< "$output"
  [ "$output" = "[
  301,
  302,
  303,
  304
]" ]
}

@test "fix_review_pr_numbers_json skips PRs already owned by an active fix-review pane" {
  PRS_STATE_JSON=$(cat <<'JSON'
[
  {"number": 400, "pipelineState": "changes_requested"},
  {"number": 401, "pipelineState": "conflict"}
]
JSON
)
  export PRS_STATE_JSON
  ts_seed_registry "fix-review-pr-400|fix-review|terminal_1|alive"
  run fix_review_pr_numbers_json
  [ "$status" -eq 0 ]
  run jq 'sort' <<< "$output"
  [ "$output" = "[
  401
]" ]
}

# ── next_implement_name ─────────────────────────────────────────────────────

@test "next_implement_name returns implement-1 for empty registry" {
  run next_implement_name
  [ "$status" -eq 0 ]
  [ "$output" = "implement-1" ]
}

@test "next_implement_name increments past existing implement-N panes" {
  ts_seed_registry \
    "implement-1|implement|terminal_1|alive" \
    "implement-3|implement|terminal_2|alive" \
    "dev-server|dev-server|terminal_3|alive"
  run next_implement_name
  [ "$status" -eq 0 ]
  [ "$output" = "implement-4" ]
}
