#!/usr/bin/env bats
# shellcheck disable=SC1091,SC2030,SC2031
# Tests for scripts/lib/github.sh normalize_prs_json — the heart of the PR
# state machine. Every downstream decision (review pane vs fix-review pane,
# dashboard colour, skip reasons) depends on this normalization, so it gets
# tight coverage.

load helpers

setup() {
  ts_setup
  ts_load_common
  # shellcheck source=../lib/github.sh
  source "${TS_LIB_DIR}/github.sh"
}

teardown() {
  ts_teardown
}

# Helper: feed a PR list into normalize_prs_json and return just the
# pipelineState for the PR with the given number.
state_for_pr() {
  local number="$1"
  PRS_JSON="$PRS_JSON_INPUT" normalize_prs_json \
    | jq -r --argjson n "$number" '.[] | select(.number == $n) | .pipelineState'
}

# Helper: same as above but returns checksState.
checks_for_pr() {
  local number="$1"
  PRS_JSON="$PRS_JSON_INPUT" normalize_prs_json \
    | jq -r --argjson n "$number" '.[] | select(.number == $n) | .checksState'
}

@test "normalize_prs_json handles empty input" {
  export PRS_JSON_INPUT='[]'
  result=$(PRS_JSON="$PRS_JSON_INPUT" normalize_prs_json)
  [ "$result" = "[]" ]
}

@test "pipelineState is 'draft' for draft PRs regardless of other fields" {
  export PRS_JSON_INPUT='[{"number":1,"isDraft":true,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[]}]'
  [ "$(state_for_pr 1)" = "draft" ]
}

@test "pipelineState is 'review_pending' for unreviewed PRs" {
  export PRS_JSON_INPUT='[{"number":2,"isDraft":false,"reviewDecision":"REVIEW_REQUIRED","mergeStateStatus":"CLEAN","statusCheckRollup":[]}]'
  [ "$(state_for_pr 2)" = "review_pending" ]
}

@test "pipelineState is 'review_pending' when reviewDecision is null" {
  export PRS_JSON_INPUT='[{"number":3,"isDraft":false,"reviewDecision":null,"mergeStateStatus":"CLEAN","statusCheckRollup":[]}]'
  [ "$(state_for_pr 3)" = "review_pending" ]
}

@test "pipelineState is 'changes_requested' for PRs with CHANGES_REQUESTED decision" {
  export PRS_JSON_INPUT='[{"number":4,"isDraft":false,"reviewDecision":"CHANGES_REQUESTED","mergeStateStatus":"CLEAN","statusCheckRollup":[]}]'
  [ "$(state_for_pr 4)" = "changes_requested" ]
}

@test "pipelineState is 'conflict' when mergeStateStatus is DIRTY regardless of approval" {
  export PRS_JSON_INPUT='[{"number":5,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"DIRTY","statusCheckRollup":[]}]'
  [ "$(state_for_pr 5)" = "conflict" ]
}

@test "pipelineState is 'approved_ready' when APPROVED + CLEAN + passing checks" {
  export PRS_JSON_INPUT='[{"number":6,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}]'
  [ "$(state_for_pr 6)" = "approved_ready" ]
}

@test "pipelineState is 'approved_pending' when APPROVED + CLEAN + pending checks" {
  export PRS_JSON_INPUT='[{"number":7,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":null}]}]'
  [ "$(state_for_pr 7)" = "approved_pending" ]
}

@test "pipelineState is 'approved_checks_failed' when APPROVED but any check failed" {
  export PRS_JSON_INPUT='[{"number":8,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}]}]'
  [ "$(state_for_pr 8)" = "approved_checks_failed" ]
}

@test "pipelineState is 'approved_checks_failed' when check is CANCELLED" {
  export PRS_JSON_INPUT='[{"number":9,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"CANCELLED"}]}]'
  [ "$(state_for_pr 9)" = "approved_checks_failed" ]
}

@test "pipelineState is 'merge_blocked' when APPROVED but mergeStateStatus is neither CLEAN nor HAS_HOOKS" {
  export PRS_JSON_INPUT='[{"number":10,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"BLOCKED","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}]'
  [ "$(state_for_pr 10)" = "merge_blocked" ]
}

@test "pipelineState treats HAS_HOOKS as mergeable" {
  export PRS_JSON_INPUT='[{"number":11,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"HAS_HOOKS","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}]'
  [ "$(state_for_pr 11)" = "approved_ready" ]
}

@test "pipelineState treats UNKNOWN mergeStateStatus as mergeable" {
  # UNKNOWN is returned by GitHub when status is not yet computed; treating it
  # as "blocked" would cause flaky pane allocation. The state machine trusts
  # the review decision here.
  export PRS_JSON_INPUT='[{"number":12,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"UNKNOWN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]}]'
  [ "$(state_for_pr 12)" = "approved_ready" ]
}

@test "checksState reports failing/pending/passing/unknown correctly" {
  export PRS_JSON_INPUT='[
    {"number":20,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[]},
    {"number":21,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"SUCCESS"}]},
    {"number":22,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"IN_PROGRESS","conclusion":null}]},
    {"number":23,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}]}
  ]'
  [ "$(checks_for_pr 20)" = "unknown" ]
  [ "$(checks_for_pr 21)" = "passing" ]
  [ "$(checks_for_pr 22)" = "pending" ]
  [ "$(checks_for_pr 23)" = "failing" ]
}

@test "checksState treats NEUTRAL and SKIPPED as passing" {
  export PRS_JSON_INPUT='[{"number":30,"isDraft":false,"reviewDecision":"APPROVED","mergeStateStatus":"CLEAN","statusCheckRollup":[{"status":"COMPLETED","conclusion":"NEUTRAL"},{"status":"COMPLETED","conclusion":"SKIPPED"}]}]'
  [ "$(checks_for_pr 30)" = "passing" ]
}

@test "changes_requested takes precedence over conflict and failing checks" {
  # If the reviewer requested changes, the PR belongs to fix-review no matter
  # what else is wrong with it. This prevents the planner from looping on CI
  # noise before the change request is even addressed.
  export PRS_JSON_INPUT='[{"number":40,"isDraft":false,"reviewDecision":"CHANGES_REQUESTED","mergeStateStatus":"DIRTY","statusCheckRollup":[{"status":"COMPLETED","conclusion":"FAILURE"}]}]'
  [ "$(state_for_pr 40)" = "changes_requested" ]
}

@test "draft takes precedence over changes_requested" {
  # Draft PRs should never be treated as actionable; they are still a work
  # in progress.
  export PRS_JSON_INPUT='[{"number":41,"isDraft":true,"reviewDecision":"CHANGES_REQUESTED","mergeStateStatus":"CLEAN","statusCheckRollup":[]}]'
  [ "$(state_for_pr 41)" = "draft" ]
}
