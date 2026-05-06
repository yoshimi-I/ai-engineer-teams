#!/usr/bin/env bash

gh_cached() {
  local key="$1"; shift
  local cache_file="${CACHE_DIR}/${key}"
  local err_file="${CACHE_DIR}/${key}.err"
  if [ -f "$cache_file" ]; then
    local age=$(( $(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null || echo 0) ))
    if [ "$age" -lt "$CACHE_TTL" ]; then
      case "$key" in
        issues_json|prs_json)
          jq -e 'type == "array"' "$cache_file" >/dev/null 2>&1 && cat "$cache_file" && return
          ;;
        gh_user|latest_merged_pr)
          local val; val=$(cat "$cache_file")
          [ -n "$val" ] && [ "$val" != "0" ] && echo "$val" && return
          ;;
        *)
          cat "$cache_file" && return
          ;;
      esac
    fi
  fi

  local default result
  case "$key" in
    issues_json|prs_json) default="[]" ;;
    latest_merged_pr|gh_user) default="" ;;
    *) default="0" ;;
  esac

  if result=$("$@" 2>"$err_file"); then
    rm -f "$err_file"
    printf '%s' "$result" | atomic_write "$cache_file"
    echo "$result"
    return
  fi

  # Keep the UI structurally valid even when gh auth/network is broken.
  printf '%s' "$default" | atomic_write "$cache_file"
  echo "$default"
}

normalize_prs_json() {
  jq '
    def checks_state:
      ([.statusCheckRollup[]?] as $checks
      | if ($checks | length) == 0 then "unknown"
        elif any($checks[]; ((.conclusion // "") | IN("FAILURE", "CANCELLED", "TIMED_OUT", "ACTION_REQUIRED"))) then "failing"
        elif any($checks[]; (((.status // "") != "") and ((.status // "") != "COMPLETED"))) then "pending"
        elif all($checks[]; ((.conclusion // "SUCCESS") | IN("SUCCESS", "NEUTRAL", "SKIPPED"))) then "passing"
        else "unknown"
        end);
    def pr_state:
      checks_state as $checks
      | if (.isDraft // false) then "draft"
        elif .reviewDecision == "CHANGES_REQUESTED" then "changes_requested"
        elif .mergeStateStatus == "DIRTY" then "conflict"
        elif .reviewDecision == "APPROVED" and ($checks == "failing") then "approved_checks_failed"
        elif .reviewDecision == "APPROVED" and (((.mergeStateStatus // "UNKNOWN") | IN("CLEAN", "HAS_HOOKS", "UNKNOWN")) | not) then "merge_blocked"
        elif .reviewDecision == "APPROVED" and ($checks == "pending") then "approved_pending"
        elif .reviewDecision == "APPROVED" then "approved_ready"
        elif .reviewDecision == "REVIEW_REQUIRED" then "review_pending"
        else "review_pending"
        end;
    [.[] | . + {checksState: checks_state, pipelineState: pr_state}]
  ' <<< "${PRS_JSON:-[]}" 2>/dev/null || echo "[]"
}

refresh_github() {
  ISSUES_JSON=$(gh_cached issues_json gh issue list --state open --limit 100 --json number,title,body,labels,assignees)
  PRS_JSON=$(gh_cached prs_json gh pr list --base "${INTEGRATION_BRANCH:-develop}" --limit 30 --json number,title,headRefName,baseRefName,reviewDecision,mergeStateStatus,isDraft,statusCheckRollup,author,assignees)
  PRS_STATE_JSON=$(normalize_prs_json)
  GH_USER=$(gh_cached gh_user gh api user --jq '.login')

  # Surface a single warning when gh auth cannot resolve the current user.
  # In that case `ready_issue_numbers_json` intentionally restricts to
  # unassigned issues to preserve the parallel-agent mutex — see its header
  # comment. Logging once per refresh (not once per tick or once per jq
  # call) keeps the signal useful without drowning stderr.
  if [ -z "${GH_USER:-}" ] && command -v log >/dev/null 2>&1; then
    log "WARN" "gh auth user could not be resolved — implement panes will only pick up unassigned issues. Run 'gh auth status' to diagnose."
  fi

  # shellcheck disable=SC2034
  ISSUES=$(jq 'length' <<< "${ISSUES_JSON:-[]}" 2>/dev/null || echo 0)
  # shellcheck disable=SC2034
  # READY_ISSUES uses the same assignee-exclusion rule as ready_issue_numbers_json
  # in planner.sh: unassigned OR assigned to the current GH_USER. When GH_USER
  # cannot be resolved, we intentionally count ONLY unassigned issues. The old
  # catch-all that returned every open issue in that state undermined the
  # assignee-based mutex between parallel agents.
  #
  # Dependency scan accepts both the legacy `depends-on: #N` and the newer
  # `blocked-by: #N (type)` formats. Issues whose open dependencies are still
  # un-merged are excluded.
  READY_ISSUES=$(jq --arg me "${GH_USER:-}" '
    [.[].number] as $open
    | [.[] | select(
        (.assignees | length == 0)
        or ($me != "" and ([.assignees[]?.login] | index($me))))
      | select(([.labels[]?.name] | index("blocked") | not))
      | select(((.body // "" | [scan("(?:depends-on|blocked-by): *#([0-9]+)") | .[0] | tonumber]) as $deps
        | ([$deps[] | select(. as $d | $open | index($d))] | length) == 0))]
    | length
  ' <<< "${ISSUES_JSON:-[]}" 2>/dev/null || echo 0)
  # shellcheck disable=SC2034
  CHANGES_REQ=$(jq '[.[] | select(.pipelineState == "changes_requested")] | length' <<< "${PRS_STATE_JSON:-[]}" 2>/dev/null || echo 0)
  # shellcheck disable=SC2034
  FIX_REVIEW_READY=$(jq '
    [.[] | select(.pipelineState | IN("changes_requested", "conflict", "approved_checks_failed", "merge_blocked"))]
    | length
  ' <<< "${PRS_STATE_JSON:-[]}" 2>/dev/null || echo 0)
  LATEST_MERGED_PR=$(gh_cached latest_merged_pr gh pr list --base "${INTEGRATION_BRANCH:-develop}" --state merged --limit 1 --json number \
    --jq '.[0].number // ""')
  HAS_MERGES=false
  # shellcheck disable=SC2034
  [ -n "${LATEST_MERGED_PR:-}" ] && HAS_MERGES=true

  auto_unblock_issues
}

auto_unblock_issues() {
  local unblock_numbers
  unblock_numbers=$(jq -r '
    [.[].number] as $open
    | .[]
    | select([.labels[]?.name] | index("blocked"))
    | select(
        ((.body // "" | [scan("(?:depends-on|blocked-by): *#([0-9]+)") | .[0] | tonumber]) as $deps
          | ($deps | length) == 0 or ([$deps[] | select(. as $d | $open | index($d))] | length) == 0))
    | .number
  ' <<< "${ISSUES_JSON:-[]}" 2>/dev/null)
  local n
  for n in $unblock_numbers; do
    gh issue edit "$n" --remove-label blocked 2>/dev/null &
  done
  wait
}
