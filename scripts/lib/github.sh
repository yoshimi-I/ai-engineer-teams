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
    echo "$result" > "$cache_file"
    echo "$result"
    return
  fi

  # Keep the UI structurally valid even when gh auth/network is broken.
  echo "$default" > "$cache_file"
  echo "$default"
}

refresh_github() {
  ISSUES_JSON=$(gh_cached issues_json gh issue list --state open --limit 100 --json number,title,body,labels,assignees)
  PRS_JSON=$(gh_cached prs_json gh pr list --base "${INTEGRATION_BRANCH:-develop}" --limit 30 --json number,title,headRefName,baseRefName,reviewDecision,mergeStateStatus,isDraft,statusCheckRollup,author,assignees)
  GH_USER=$(gh_cached gh_user gh api user --jq '.login')
  # shellcheck disable=SC2034
  ISSUES=$(jq 'length' <<< "${ISSUES_JSON:-[]}" 2>/dev/null || echo 0)
  # shellcheck disable=SC2034
  READY_ISSUES=$(jq --arg me "${GH_USER:-}" '
    [.[].number] as $open
    | [.[] | select(
        (.assignees | length == 0)
        or ($me != "" and ([.assignees[]?.login] | index($me)))
        or ($me == ""))
      | select(([.labels[]?.name] | index("blocked") | not))
      | select(((.body // "" | [scan("depends-on: *#([0-9]+)") | .[0] | tonumber]) as $deps
        | ([$deps[] | select(. as $d | $open | index($d))] | length) == 0))]
    | length
  ' <<< "${ISSUES_JSON:-[]}" 2>/dev/null || echo 0)
  # shellcheck disable=SC2034
  CHANGES_REQ=$(jq '[.[] | select(.reviewDecision == "CHANGES_REQUESTED")] | length' <<< "${PRS_JSON:-[]}" 2>/dev/null || echo 0)
  # shellcheck disable=SC2034
  FIX_REVIEW_READY=$(jq '
    [.[] | select((.isDraft // false) | not)
      | select(.reviewDecision == "CHANGES_REQUESTED"
        or .mergeStateStatus == "DIRTY"
        or (.reviewDecision == "APPROVED" and ((.mergeStateStatus // "UNKNOWN") | IN("CLEAN", "HAS_HOOKS", "UNKNOWN") | not)))]
    | length
  ' <<< "${PRS_JSON:-[]}" 2>/dev/null || echo 0)
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
        ((.body // "" | [scan("depends-on: *#([0-9]+)") | .[0] | tonumber]) as $deps
          | ($deps | length) == 0 or ([$deps[] | select(. as $d | $open | index($d))] | length) == 0))
    | .number
  ' <<< "${ISSUES_JSON:-[]}" 2>/dev/null)
  local n
  for n in $unblock_numbers; do
    gh issue edit "$n" --remove-label blocked 2>/dev/null &
  done
  wait
}
