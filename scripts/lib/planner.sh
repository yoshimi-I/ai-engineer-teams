#!/usr/bin/env bash

next_implement_name() {
  local max=0 n
  while IFS='|' read -r name _role _pane _status; do
    if [[ "$name" =~ ^implement-([0-9]+)$ ]]; then
      n="${BASH_REMATCH[1]}"
      [ "$n" -gt "$max" ] && max="$n"
    fi
  done < "$PANE_REGISTRY"
  echo "implement-$((max + 1))"
}

active_implement_issues_json() {
  jq -Rn '
    [inputs
      | select(length > 0)
      | split("|")
      | select(length >= 4 and .[1] == "implement" and .[3] == "alive")
      | .[0]
      | select(test("^implement-issue-[0-9]+$"))
      | sub("^implement-issue-"; "")
      | tonumber]
  ' < "$PANE_REGISTRY"
}

active_pr_numbers_json() {
  local role="$1" prefix="$2"
  jq -Rn --arg role "$role" --arg prefix "$prefix" '
    [inputs
      | select(length > 0)
      | split("|")
      | select(length >= 4 and .[1] == $role and .[3] == "alive")
      | .[0]
      | select(test("^" + $prefix + "-pr-[0-9]+$"))
      | sub("^" + $prefix + "-pr-"; "")
      | tonumber]
  ' < "$PANE_REGISTRY"
}

review_pr_numbers_json() {
  local active
  active=$(active_pr_numbers_json "review" "review")
  jq --argjson active "$active" '
    [.[] | select(.reviewDecision != "CHANGES_REQUESTED")
      | select((.number as $n | $active | index($n) | not))
      | .number]
  ' <<< "${PRS_JSON:-[]}" 2>/dev/null || echo "[]"
}

fix_review_pr_numbers_json() {
  local active
  active=$(active_pr_numbers_json "fix-review" "fix-review")
  jq --arg me "${GH_USER:-}" --argjson active "$active" '
    [.[] | select(.reviewDecision == "CHANGES_REQUESTED")
      | select((.assignees | length == 0) or ([.assignees[]?.login] | index($me)))
      | select((.number as $n | $active | index($n) | not))
      | .number]
  ' <<< "${PRS_JSON:-[]}" 2>/dev/null || echo "[]"
}

next_review_pr_number() {
  review_pr_numbers_json | jq -r '.[0] // ""'
}

next_fix_review_pr_number() {
  fix_review_pr_numbers_json | jq -r '.[0] // ""'
}

json_has_number() {
  local number="$1" json="$2"
  jq -e --argjson n "$number" 'index($n) != null' >/dev/null 2>&1 <<< "$json"
}

ready_issue_numbers_json() {
  local active
  active=$(active_implement_issues_json)
  jq \
    --arg me "${GH_USER:-}" \
    --argjson active "$active" '
    [.[].number] as $open
    | [.[] | select((.assignees | length == 0) or ([.assignees[]?.login] | index($me)))
      | select(([.labels[]?.name] | index("blocked") | not))
      | select((.number as $n | $active | index($n) | not))
      | select(((.body // "" | [scan("depends-on: *#([0-9]+)") | .[0] | tonumber]) as $deps
        | ([$deps[] | select(. as $d | $open | index($d))] | length) == 0))
      | .number]
  ' <<< "${ISSUES_JSON:-[]}" 2>/dev/null || echo "[]"
}

next_ready_issue_number() {
  ready_issue_numbers_json | jq -r '.[0] // ""'
}

operator_request_json() {
  if [ -f "${OPERATOR_REQUEST_FILE:-}" ]; then
    jq -c '. // {status:"empty"}' "$OPERATOR_REQUEST_FILE" 2>/dev/null || jq -n '{status:"invalid"}'
  else
    jq -n '{status:"empty"}'
  fi
}

clear_operator_request() {
  [ -n "${OPERATOR_REQUEST_FILE:-}" ] || return 0
  jq -n \
    --arg ts "$(date '+%H:%M:%S')" \
    '{status:"handled", ts:$ts, request:"", intent:"general", target:"", priority:"normal"}' \
    > "$OPERATOR_REQUEST_FILE"
}

operator_target_issue_number() {
  local target="$1"
  if [[ "$target" =~ ^#?([0-9]+)$ ]]; then
    echo "${BASH_REMATCH[1]}"
  elif [[ "$target" =~ issue-([0-9]+) ]]; then
    echo "${BASH_REMATCH[1]}"
  fi
}

handle_operator_request() {
  local req status intent target request issue role pane_name
  req=$(operator_request_json)
  status=$(jq -r '.status // "empty"' <<< "$req" 2>/dev/null || echo empty)
  [ "$status" = "open" ] || return 1

  intent=$(jq -r '.intent // "general"' <<< "$req")
  target=$(jq -r '.target // ""' <<< "$req")
  request=$(jq -r '.request // ""' <<< "$req")

  case "$intent" in
    launch_role|prioritize_issue)
      issue=$(operator_target_issue_number "$target")
      if [ -n "$issue" ]; then
        pane_name="implement-issue-${issue}"
        if pane_name_active "$pane_name"; then
          record_decision "operator" "already active:${pane_name}" "$request"
          clear_operator_request
          return 0
        fi
        if add_pane "$pane_name" "implement" "$(implement_context_for_issue "$issue")" "operator: ${request:-requested issue #${issue}}"; then
          record_decision "operator" "launched:${pane_name}" "$request"
          clear_operator_request
          return 0
        fi
        record_decision "operator" "launch failed:${pane_name}" "$request"
        clear_operator_request
        return 0
      fi

      role="$target"
      case "$role" in
        review)
          local review_pr
          review_pr=$(next_review_pr_number)
          [ -n "$review_pr" ] || { record_decision "operator" "no reviewable PR" "$request"; clear_operator_request; return 0; }
          pane_name="review-pr-${review_pr}"
          if add_pane "$pane_name" "review" "$(review_context_for_pr "$review_pr")" "operator: ${request:-launch review}"; then
            record_decision "operator" "launched:${pane_name}" "$request"
            clear_operator_request
            return 0
          fi
          record_decision "operator" "launch failed:${pane_name}" "$request"
          clear_operator_request
          return 0
          ;;
        fix-review)
          local fix_pr
          fix_pr=$(next_fix_review_pr_number)
          [ -n "$fix_pr" ] || { record_decision "operator" "no actionable review changes" "$request"; clear_operator_request; return 0; }
          pane_name="fix-review-pr-${fix_pr}"
          if add_pane "$pane_name" "fix-review" "$(fix_review_context_for_pr "$fix_pr")" "operator: ${request:-launch fix-review}"; then
            record_decision "operator" "launched:${pane_name}" "$request"
            clear_operator_request
            return 0
          fi
          record_decision "operator" "launch failed:${pane_name}" "$request"
          clear_operator_request
          return 0
          ;;
        e2e-bug-hunt)
          pane_name="e2e-hunt"
          if add_pane "$pane_name" "$role" "" "operator: ${request:-launch $role}"; then
            record_decision "operator" "launched:${pane_name}" "$request"
            clear_operator_request
            return 0
          fi
          record_decision "operator" "launch failed:${pane_name}" "$request"
          clear_operator_request
          return 0
          ;;
        dev-server|e2e|watch-main|improve)
          if add_pane "$role" "$role" "" "operator: ${request:-launch $role}"; then
            record_decision "operator" "launched:${role}" "$request"
            clear_operator_request
            return 0
          fi
          record_decision "operator" "launch failed:${role}" "$request"
          clear_operator_request
          return 0
          ;;
      esac
      ;;
    stop_role)
      role="$target"
      if valid_role "$role"; then
        kill_role "$role"
        reconcile_panes
        record_decision "operator" "stopped:${role}" "$request"
        clear_operator_request
        return 0
      fi
      ;;
  esac

  return 1
}

implement_context_for_issue() {
  local issue="$1"
  printf 'You are assigned to GitHub issue #%s. Work only on issue #%s in this cycle. Do not auto-select another issue unless this issue is already closed, assigned to someone else, or already has an open PR.' "$issue" "$issue"
}

review_context_for_pr() {
  local pr="$1"
  printf 'You are assigned to GitHub PR #%s for review/merge handling. Work only on PR #%s in this cycle. Do not auto-select another PR unless this PR is already closed, merged, or no longer needs review/merge work.' "$pr" "$pr"
}

fix_review_context_for_pr() {
  local pr="$1"
  printf 'You are assigned to GitHub PR #%s for requested-change fixes. Work only on PR #%s in this cycle. Do not auto-select another PR unless this PR is already closed, merged, or no longer has actionable requested changes.' "$pr" "$pr"
}

build_ai_context() {
  local active_json post_merge_spawned dev_health
  active_json=$(active_panes_json)
  dev_health=$(dev_health_json)
  post_merge_spawned=false
  post_merge_already_spawned && post_merge_spawned=true

  jq -n \
    --argjson issues "${ISSUES_JSON:-[]}" \
    --argjson prs "${PRS_JSON:-[]}" \
    --argjson active "$active_json" \
    --argjson dev_health "$dev_health" \
    --arg latest_merged_pr "${LATEST_MERGED_PR:-}" \
    --argjson post_merge_spawned "$post_merge_spawned" \
    --argjson operator_request "$(operator_request_json)" \
    --argjson max_alive "$MAX_ALIVE" \
    --argjson max_implement "$MAX_IMPLEMENT" \
    --argjson ready_issue_numbers "$(ready_issue_numbers_json)" \
    --argjson review_pr_numbers "$(review_pr_numbers_json)" \
    --argjson fix_review_pr_numbers "$(fix_review_pr_numbers_json)" \
    --arg next_implement "$(next_implement_name)" \
    --arg me "${GH_USER:-}" \
    --argjson has_dev_target "$(has_dev_target && echo true || echo false)" \
    --argjson auto_dev_server "$([ "$AUTO_DEV_SERVER" = "true" ] && echo true || echo false)" \
    --argjson auto_watch_main "$([ "$AUTO_WATCH_MAIN" = "true" ] && echo true || echo false)" \
    --argjson auto_improve "$([ "$AUTO_IMPROVE" = "true" ] && echo true || echo false)" \
    '{
      limits: {max_alive: $max_alive, max_implement: $max_implement},
      automation: {dev_server: $auto_dev_server, watch_main: $auto_watch_main, improve: $auto_improve},
      project: {has_dev_target: $has_dev_target},
      dev_server: $dev_health,
      next_names: {implement: $next_implement},
      ready_issue_numbers: $ready_issue_numbers,
      review_pr_numbers: $review_pr_numbers,
      fix_review_pr_numbers: $fix_review_pr_numbers,
      active_panes: $active,
      operator_request: $operator_request,
      issues: {
        unassigned_count: ([$issues[] | select(.assignees | length == 0)] | length),
        ready_count: (
          [$issues[].number] as $open
          | [$issues[] | select((.assignees | length == 0) or ([.assignees[]?.login] | index($me)))
            | select(([.labels[]?.name] | index("blocked") | not))
            | select(((.body // "" | [scan("depends-on: *#([0-9]+)") | .[0] | tonumber]) as $deps
              | ([$deps[] | select(. as $d | $open | index($d))] | length) == 0))]
          | length
        ),
        open: $issues
      },
      pull_requests: {
        changes_requested_count: ([$prs[] | select(.reviewDecision == "CHANGES_REQUESTED")] | length),
        review_ready_count: ($review_pr_numbers | length),
        fix_review_ready_count: ($fix_review_pr_numbers | length),
        open: $prs
      },
      latest_merged_pr: $latest_merged_pr,
      post_merge_already_spawned: $post_merge_spawned
    }'
}

extract_json_object() {
  sed -n '/^{/,/^}/p' | sed '1,$s/^```json$//;1,$s/^```$//'
}

ai_plan() {
  [ -f "$AI_PLAN_PROMPT" ] || return 1
  local context raw plan
  context=$(build_ai_context)
  record_decision "ai" "asking AI planner" "building pane action plan"
  raw=$(kiro-cli chat --no-interactive --trust-all-tools --resume \
    "$(cat "$AI_PLAN_PROMPT")

Context JSON:
$context" 2>/dev/null || true)
  plan=$(printf '%s\n' "$raw" | extract_json_object)
  if jq -e '.actions and (.actions | type == "array")' >/dev/null 2>&1 <<< "$plan"; then
    printf '%s\n' "$plan" > "$AI_PLAN_FILE"
    printf '%s\n' "$plan"
    return 0
  fi
  record_decision "fallback" "AI planner returned no valid plan" "using conservative fallback rules"
  return 1
}

valid_role() {
  case "$1" in
    dev-server|implement|review|fix-review|e2e|e2e-bug-hunt|watch-main|improve) return 0 ;;
    *) return 1 ;;
  esac
}

execute_ai_plan() {
  local plan="$1" changed=0 launched=0 launched_implement=0 launched_roles="" skipped="" issue_num pr_num context reason
  while IFS=$'\t' read -r role reason; do
    if ! valid_role "$role"; then
      skipped="${skipped} invalid-stop:${role}"
      continue
    fi
    if [ "$role" = "implement" ]; then
      skipped="${skipped} stop-implement-denied"
      continue
    fi
    if role_active "$role"; then
      kill_role "$role"
      changed=$((changed + 1))
      launched_roles="${launched_roles} stopped-${role}(${reason:-no reason})"
    fi
  done < <(jq -r '.stop[]? | [.role, (.reason // "")] | @tsv' <<< "$plan" 2>/dev/null)

  while IFS=$'\t' read -r role name reason; do
    if ! valid_role "$role"; then
      skipped="${skipped} invalid:${role}"
      continue
    fi
    if limit_reached "$(total_alive)" "$MAX_ALIVE"; then
      skipped="${skipped} max-alive"
      break
    fi
    if [ "$role" != "implement" ] && singleton_role "$role" && role_active "$role"; then
      skipped="${skipped} active:${role}"
      continue
    fi
    case "$role" in
      dev-server)
        if [ "$AUTO_DEV_SERVER" != "true" ]; then skipped="${skipped} dev-disabled"; continue; fi
        if ! has_dev_target; then skipped="${skipped} no-dev-target"; continue; fi
        ;;
      implement)
        if [ "${READY_ISSUES:-0}" -le 0 ]; then skipped="${skipped} no-ready-issues"; continue; fi
        if limit_reached "$(count_alive "implement")" "$MAX_IMPLEMENT"; then skipped="${skipped} max-implement"; continue; fi
        if [ "$launched_implement" -ge "${READY_ISSUES:-0}" ]; then skipped="${skipped} no-more-ready-issues"; continue; fi
        issue_num="$(next_ready_issue_number)"
        if [ -z "$issue_num" ]; then skipped="${skipped} no-ready-issue-number"; continue; fi
        name="implement-issue-${issue_num}"
        launched_implement=$((launched_implement + 1))
        ;;
      fix-review)
        pr_num=""
        local fix_candidates
        fix_candidates="$(fix_review_pr_numbers_json)"
        if [[ "$name" =~ ^fix-review-pr-([0-9]+)$ ]]; then
          pr_num="${BASH_REMATCH[1]}"
          if ! json_has_number "$pr_num" "$fix_candidates"; then
            skipped="${skipped} not-actionable:${name}"
            continue
          fi
        else
          pr_num="$(jq -r '.[0] // ""' <<< "$fix_candidates")"
        fi
        if [ -z "$pr_num" ]; then skipped="${skipped} no-actionable-review-changes"; continue; fi
        name="fix-review-pr-${pr_num}"
        ;;
      review)
        pr_num=""
        local review_candidates
        review_candidates="$(review_pr_numbers_json)"
        if [[ "$name" =~ ^review-pr-([0-9]+)$ ]]; then
          pr_num="${BASH_REMATCH[1]}"
          if ! json_has_number "$pr_num" "$review_candidates"; then
            skipped="${skipped} not-reviewable:${name}"
            continue
          fi
        else
          pr_num="$(jq -r '.[0] // ""' <<< "$review_candidates")"
        fi
        if [ -z "$pr_num" ]; then skipped="${skipped} no-reviewable-pr"; continue; fi
        name="review-pr-${pr_num}"
        ;;
      e2e)
        if ! role_active "dev-server"; then skipped="${skipped} no-dev-server"; continue; fi
        ;;
      e2e-bug-hunt)
        if ! role_active "dev-server"; then skipped="${skipped} no-dev-server"; continue; fi
        if ! post_merge_due; then skipped="${skipped} no-new-merge"; continue; fi
        ;;
      watch-main)
        if ! role_active "dev-server"; then skipped="${skipped} no-dev-server"; continue; fi
        if [ "$AUTO_WATCH_MAIN" != "true" ] || ! post_merge_due; then
          skipped="${skipped} watch-disabled"
          continue
        fi
        ;;
      improve)
        if [ "$AUTO_IMPROVE" != "true" ] || [ "${ISSUES:-0}" -ne 0 ]; then
          skipped="${skipped} improve-disabled-or-issues"
          continue
        fi
        ;;
    esac
    [ -n "$name" ] && [ "$name" != "null" ] || name="$role"
    if pane_name_active "$name"; then
      skipped="${skipped} active-name:${name}"
      continue
    fi
    context=""
    if [ "$role" = "implement" ] && [[ "$name" =~ ^implement-issue-([0-9]+)$ ]]; then
      context="$(implement_context_for_issue "${BASH_REMATCH[1]}")"
    elif [ "$role" = "review" ] && [[ "$name" =~ ^review-pr-([0-9]+)$ ]]; then
      context="$(review_context_for_pr "${BASH_REMATCH[1]}")"
    elif [ "$role" = "fix-review" ] && [[ "$name" =~ ^fix-review-pr-([0-9]+)$ ]]; then
      context="$(fix_review_context_for_pr "${BASH_REMATCH[1]}")"
    fi
    if add_pane "$name" "$role" "$context" "$reason"; then
      changed=$((changed + 1))
      launched=$((launched + 1))
      launched_roles="${launched_roles} ${name}:${role}"
    else
      skipped="${skipped} launch-failed:${name}"
    fi
  done < <(jq -r '.actions[]? | [.role, (.name // .role), (.reason // "")] | @tsv' <<< "$plan" 2>/dev/null)

  if jq -e '.actions[]? | .role == "e2e" or .role == "e2e-bug-hunt" or .role == "watch-main" or .role == "improve"' >/dev/null 2>&1 <<< "$plan"; then
    [ "$launched" -gt 0 ] && mark_post_merge_spawned
  fi

  if [ "$changed" -gt 0 ]; then
    record_decision "ai" "changed:${launched_roles# }" "skipped:${skipped# }"
    return 0
  fi

  local skip_reasons
  skip_reasons=$(jq -r '[.skip[]? | .role + ":" + .reason] | join(" | ")' <<< "$plan" 2>/dev/null)
  [ -n "$skip_reasons" ] && [ "$skip_reasons" != "null" ] || skip_reasons="skipped:${skipped# }"
  record_decision "ai" "no pane launched" "$skip_reasons"
  return 1
}

fallback_scale() {
  local cur_impl; cur_impl=$(count_alive "implement")
  local cur_review; cur_review=$(count_alive "review")
  local cur_fix;  cur_fix=$(count_alive "fix-review")
  local cur_e2e;  cur_e2e=$(count_alive "e2e-bug-hunt")
  local cur_watch=0 cur_imp=0 issue_num pr_num
  local launched=""
  [ "$AUTO_WATCH_MAIN" = "true" ] && cur_watch=$(count_alive "watch-main")
  [ "$AUTO_IMPROVE" = "true" ] && cur_imp=$(count_alive "improve")

  local desired=0
  if [ "$AUTO_DEV_SERVER" = "true" ] && has_dev_target && ! role_active "dev-server" && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    if add_pane "dev-server" "dev-server" "" "fallback: dev target exists and dev-server is not active"; then
      launched="${launched} dev-server"
    fi
  fi

  if [ "${READY_ISSUES:-0}" -gt 0 ]; then
    desired="$READY_ISSUES"
    if [ "$MAX_IMPLEMENT" -gt 0 ] && [ "$MAX_IMPLEMENT" -lt "$desired" ]; then
      desired="$MAX_IMPLEMENT"
    fi
  fi
  while [ "$cur_impl" -lt "$desired" ] && below_limit "$(total_alive)" "$MAX_ALIVE"; do
    local impl_name
    issue_num="$(next_ready_issue_number)"
    [ -n "$issue_num" ] || break
    impl_name="implement-issue-${issue_num}"
    if add_pane "$impl_name" "implement" "$(implement_context_for_issue "$issue_num")" "fallback: ready issue #${issue_num}"; then
      launched="${launched} ${impl_name}"
      cur_impl=$((cur_impl + 1))
    else
      break
    fi
  done

  pr_num="$(next_review_pr_number)"
  if [ -n "$pr_num" ] && [ "$cur_review" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    if add_pane "review-pr-${pr_num}" "review" "$(review_context_for_pr "$pr_num")" "fallback: PR #${pr_num} needs review/merge handling"; then
      launched="${launched} review-pr-${pr_num}"
    fi
  fi

  pr_num="$(next_fix_review_pr_number)"
  if [ -n "$pr_num" ] && [ "$cur_fix" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    if add_pane "fix-review-pr-${pr_num}" "fix-review" "$(fix_review_context_for_pr "$pr_num")" "fallback: PR #${pr_num} has actionable requested changes"; then
      launched="${launched} fix-review-pr-${pr_num}"
    fi
  fi

  if post_merge_due && role_active "dev-server" && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    if [ "$cur_e2e" -eq 0 ]; then
      if add_pane "e2e-hunt" "e2e-bug-hunt" "" "fallback: new merge detected and dev-server is active"; then
        launched="${launched} e2e-hunt"
      fi
    fi
    if [ "$AUTO_WATCH_MAIN" = "true" ] && [ "$cur_watch" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
      if add_pane "watch-main" "watch-main" "" "fallback: watch-main enabled after merge"; then
        launched="${launched} watch-main"
      fi
    fi
    if [ "$AUTO_IMPROVE" = "true" ] && [ "$cur_imp" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
      if add_pane "improve" "improve" "" "fallback: improve enabled after merge"; then
        launched="${launched} improve"
      fi
    fi
    [ -n "$launched" ] && mark_post_merge_spawned
  fi

  if [ -n "$launched" ]; then
    record_decision "fallback" "launched:${launched# }" "conservative rule matched"
  else
    record_decision "fallback" "idle" "no rule matched"
  fi
}

scale() {
  update_pane_status
  local alive; alive=$(total_alive)

  if handle_operator_request; then
    return
  fi

  if limit_reached "$alive" "$MAX_ALIVE"; then
    record_decision "guard" "max alive reached" "${alive}/${MAX_ALIVE} panes active"
    return
  fi

  if [ "$AI_ORCHESTRATION" = "true" ]; then
    local plan
    if plan=$(ai_plan); then
      execute_ai_plan "$plan" && return
    fi
  fi

  fallback_scale
}
