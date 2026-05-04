#!/usr/bin/env bash

write_orchestrator_status() {
  local state="$1" detail="$2"
  jq -n \
    --arg state "$state" \
    --arg detail "$detail" \
    --arg ts "$(date '+%H:%M:%S')" \
    --arg source "$LAST_PLAN_SOURCE" \
    --arg summary "$LAST_DECISION_SUMMARY" \
    '{
      agent: "orchestrator",
      prompt: "orchestrator-plan",
      state: $state,
      detail: $detail,
      issue: "",
      pr: "",
      branch: "",
      cycle: 0,
      errors: 0,
      ts: $ts,
      plan_source: $source,
      summary: $summary
    }' > "$ORCH_STATUS_FILE"
}

record_decision() {
  local source="$1" summary="$2" detail="$3"
  LAST_PLAN_SOURCE="$source"
  LAST_DECISION_SUMMARY="$summary"
  LAST_DECISION_DETAIL="$detail"
  LAST_DECISION_TS="$(date '+%H:%M:%S')"
  jq -n \
    --arg source "$source" \
    --arg summary "$summary" \
    --arg detail "$detail" \
    --arg ts "$LAST_DECISION_TS" \
    --argjson alive "$(total_alive 2>/dev/null || echo 0)" \
    --argjson issues "${ISSUES:-0}" \
    --argjson ready_issues "${READY_ISSUES:-0}" \
    --argjson changes "${CHANGES_REQ:-0}" \
    --argjson fix_ready "${FIX_REVIEW_READY:-0}" \
    --arg latest_merged_pr "${LATEST_MERGED_PR:-}" \
    '{
      source: $source,
      summary: $summary,
      detail: $detail,
      ts: $ts,
      alive: $alive,
      unassigned_issues: $issues,
      ready_issues: $ready_issues,
      changes_requested: $changes,
      fix_review_ready: $fix_ready,
      latest_merged_pr: $latest_merged_pr
    }' > "$DECISION_FILE"
  write_orchestrator_status "🧠 deciding" "$summary"
}

post_merge_due() {
  [ -n "${LATEST_MERGED_PR:-}" ] || return 1
  local last=""
  [ -f "$POST_MERGE_STATE" ] && last=$(cat "$POST_MERGE_STATE")
  [ "$last" != "$LATEST_MERGED_PR" ]
}

mark_post_merge_spawned() {
  [ -n "${LATEST_MERGED_PR:-}" ] && echo "$LATEST_MERGED_PR" > "$POST_MERGE_STATE"
}

post_merge_already_spawned() {
  [ -n "${LATEST_MERGED_PR:-}" ] || return 1
  local last=""
  [ -f "$POST_MERGE_STATE" ] && last=$(cat "$POST_MERGE_STATE")
  [ "$last" = "$LATEST_MERGED_PR" ]
}

limit_reached() {
  local current="$1" max="$2"
  [ "$max" -gt 0 ] && [ "$current" -ge "$max" ]
}

below_limit() {
  ! limit_reached "$1" "$2"
}
