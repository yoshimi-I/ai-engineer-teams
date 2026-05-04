#!/usr/bin/env bash

gh_cached() {
  local key="$1"; shift
  local cache_file="${CACHE_DIR}/${key}"
  if [ -f "$cache_file" ]; then
    local age=$(( $(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null || echo 0) ))
    [ $age -lt $CACHE_TTL ] && cat "$cache_file" && return
  fi
  local result; result=$("$@" 2>/dev/null || echo "0")
  echo "$result" > "$cache_file"; echo "$result"
}

refresh_github() {
  ISSUES_JSON=$(gh_cached issues_json gh issue list --state open --limit 100 --json number,title,body,labels,assignees)
  PRS_JSON=$(gh_cached prs_json gh pr list --limit 30 --json number,title,headRefName,reviewDecision,author,assignees)
  GH_USER=$(gh_cached gh_user gh api user --jq '.login')
  ISSUES=$(jq '[.[] | select(.assignees | length == 0)] | length' <<< "${ISSUES_JSON:-[]}" 2>/dev/null || echo 0)
  READY_ISSUES=$(jq '
    [.[].number] as $open
    | [.[] | select(.assignees | length == 0)
      | select(([.labels[]?.name] | index("blocked") | not))
      | select(((.body // "" | [scan("depends-on: *#([0-9]+)") | .[0] | tonumber]) as $deps
        | ([$deps[] | select(. as $d | $open | index($d))] | length) == 0))]
    | length
  ' <<< "${ISSUES_JSON:-[]}" 2>/dev/null || echo 0)
  CHANGES_REQ=$(jq '[.[] | select(.reviewDecision == "CHANGES_REQUESTED")] | length' <<< "${PRS_JSON:-[]}" 2>/dev/null || echo 0)
  FIX_REVIEW_READY=$(jq --arg me "${GH_USER:-}" '
    [.[] | select(.reviewDecision == "CHANGES_REQUESTED")
      | select((.assignees | length == 0) or ([.assignees[]?.login] | index($me)))]
    | length
  ' <<< "${PRS_JSON:-[]}" 2>/dev/null || echo 0)
  LATEST_MERGED_PR=$(gh_cached latest_merged_pr gh pr list --state merged --limit 1 --json number \
    --jq '.[0].number // ""')
  HAS_MERGES=false
  [ -n "${LATEST_MERGED_PR:-}" ] && HAS_MERGES=true
}
