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
    [.[] | select((.isDraft // false) | not)
      | select(.reviewDecision != "CHANGES_REQUESTED")
      | select((.mergeStateStatus // "UNKNOWN") != "DIRTY")
      | select((.reviewDecision == "APPROVED" and ((.mergeStateStatus // "UNKNOWN") | IN("CLEAN", "HAS_HOOKS", "UNKNOWN") | not)) | not)
      | select((.number as $n | $active | index($n) | not))
      | .number]
  ' <<< "${PRS_JSON:-[]}" 2>/dev/null || echo "[]"
}

fix_review_pr_numbers_json() {
  local active
  active=$(active_pr_numbers_json "fix-review" "fix-review")
  jq --argjson active "$active" '
    [.[] | select((.isDraft // false) | not)
      | select(.reviewDecision == "CHANGES_REQUESTED"
        or .mergeStateStatus == "DIRTY"
        or (.reviewDecision == "APPROVED" and ((.mergeStateStatus // "UNKNOWN") | IN("CLEAN", "HAS_HOOKS", "UNKNOWN") | not)))
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
    | [.[] | select(
        (.assignees | length == 0)
        or ($me != "" and ([.assignees[]?.login] | index($me)))
        or ($me == ""))
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
        dev-server|e2e|watch-main|improve|ui-audit)
          if add_pane "$role" "$role" "" "operator: ${request:-launch $role}"; then
            record_decision "operator" "launched:${role}" "$request"
            clear_operator_request
            return 0
          fi
          record_decision "operator" "launch failed:${role}" "$request"
          clear_operator_request
          return 0
          ;;
        create-issue|feature-discovery)
          if add_pane "$role" "$role" "$request" "operator: ${request:-launch $role}"; then
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
    general)
      if [ -n "$request" ]; then
        pane_name="create-issue"
        if ! pane_name_active "$pane_name"; then
          if add_pane "$pane_name" "create-issue" "$request" "operator: ${request}"; then
            record_decision "operator" "launched:${pane_name}" "$request"
            clear_operator_request
            return 0
          fi
        fi
        record_decision "operator" "general request noted" "$request"
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
    --argjson max_fix_review "$MAX_FIX_REVIEW" \
    --argjson ready_issue_numbers "$(ready_issue_numbers_json)" \
    --argjson review_pr_numbers "$(review_pr_numbers_json)" \
    --argjson fix_review_pr_numbers "$(fix_review_pr_numbers_json)" \
    --arg next_implement "$(next_implement_name)" \
    --arg integration_branch "${INTEGRATION_BRANCH:-develop}" \
    --arg stable_branch "${STABLE_BRANCH:-main}" \
    --arg me "${GH_USER:-}" \
    --argjson has_dev_target "$(has_dev_target && echo true || echo false)" \
    --argjson auto_dev_server "$([ "$AUTO_DEV_SERVER" = "true" ] && echo true || echo false)" \
    --argjson auto_watch_main "$([ "$AUTO_WATCH_MAIN" = "true" ] && echo true || echo false)" \
    --argjson auto_improve "$([ "$AUTO_IMPROVE" = "true" ] && echo true || echo false)" \
    --argjson auto_ui_audit "$([ "$AUTO_UI_AUDIT" = "true" ] && echo true || echo false)" \
    '{
      limits: {max_alive: $max_alive, max_implement: $max_implement, max_fix_review: $max_fix_review},
      automation: {dev_server: $auto_dev_server, watch_main: $auto_watch_main, improve: $auto_improve, ui_audit: $auto_ui_audit},
      project: {has_dev_target: $has_dev_target, integration_branch: $integration_branch, stable_branch: $stable_branch},
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
          | [$issues[] | select(
              (.assignees | length == 0)
              or ($me != "" and ([.assignees[]?.login] | index($me)))
              or ($me == ""))
            | select(([.labels[]?.name] | index("blocked") | not))
            | select(((.body // "" | [scan("depends-on: *#([0-9]+)") | .[0] | tonumber]) as $deps
              | ([$deps[] | select(. as $d | $open | index($d))] | length) == 0))]
          | length
        ),
        open: $issues
      },
      pull_requests: {
        changes_requested_count: ([$prs[] | select(.reviewDecision == "CHANGES_REQUESTED")] | length),
        conflict_count: ([$prs[] | select(.mergeStateStatus == "DIRTY")] | length),
        blocked_merge_count: ([$prs[] | select((.reviewDecision == "APPROVED") and ((.mergeStateStatus // "UNKNOWN") | IN("CLEAN", "HAS_HOOKS", "UNKNOWN") | not))] | length),
        review_ready_count: ($review_pr_numbers | length),
        fix_review_ready_count: ($fix_review_pr_numbers | length),
        open: $prs
      },
      latest_merged_pr: $latest_merged_pr,
      post_merge_already_spawned: $post_merge_spawned
    }'
}

extract_json_object() {
  # Try multiple extraction strategies
  local input
  input=$(cat)
  # Strategy 1: find JSON between ```json ... ``` markers
  local from_fence
  # shellcheck disable=SC2016
  from_fence=$(printf '%s\n' "$input" | sed -n '/^```json/,/^```/{/^```/d;p}')
  if [ -n "$from_fence" ] && jq -e '.' >/dev/null 2>&1 <<< "$from_fence"; then
    printf '%s\n' "$from_fence"
    return
  fi
  # Strategy 2: find first { to last } (greedy)
  local braces
  braces=$(printf '%s\n' "$input" | sed -n '/{/,/}/p' | sed -n '1,/}[[:space:]]*$/p')
  if [ -n "$braces" ] && jq -e '.' >/dev/null 2>&1 <<< "$braces"; then
    printf '%s\n' "$braces"
    return
  fi
  # Strategy 3: try the whole input as JSON
  if jq -e '.' >/dev/null 2>&1 <<< "$input"; then
    printf '%s\n' "$input"
    return
  fi
  # Strategy 4: original approach
  printf '%s\n' "$input" | sed -n '/^{/,/^}/p'
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
  printf '%s\n' "$raw" > "${CACHE_DIR}/orchestrator_plan.raw"
  # Strip ANSI escape sequences before parsing
  raw=$(printf '%s\n' "$raw" | sed $'s/\033\[[0-9;]*m//g' | sed $'s/\033\[[0-9;]*[A-Za-z]//g')
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
    dev-server|implement|review|fix-review|e2e|e2e-bug-hunt|ui-audit|watch-main|improve|feature-discovery|create-issue) return 0 ;;
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
      launched_roles="${launched_roles} ${role}を停止(${reason:-理由なし})"
    fi
  done < <(jq -r '.stop[]? | [.role, (.reason // "")] | @tsv' <<< "$plan" 2>/dev/null)

  while IFS=$'\t' read -r role name reason; do
    if ! valid_role "$role"; then
      skipped="${skipped} invalid:${role}"
      continue
    fi
    if limit_reached "$(total_alive)" "$MAX_ALIVE"; then
      skipped="${skipped} 上限到達:稼働pane数"
      break
    fi
    if [ "$role" != "implement" ] && singleton_role "$role" && role_active "$role"; then
      skipped="${skipped} active:${role}"
      continue
    fi
    case "$role" in
      dev-server)
        if [ "$AUTO_DEV_SERVER" != "true" ]; then skipped="${skipped} dev-server自動起動なし"; continue; fi
        if ! has_dev_target; then skipped="${skipped} dev対象なし"; continue; fi
        ;;
      implement)
        if [ "${READY_ISSUES:-0}" -le 0 ]; then skipped="${skipped} ready issueなし"; continue; fi
        if limit_reached "$(count_alive "implement")" "$MAX_IMPLEMENT"; then skipped="${skipped} 実装pane上限"; continue; fi
        if [ "$launched_implement" -ge "${READY_ISSUES:-0}" ]; then skipped="${skipped} 追加ready issueなし"; continue; fi
        issue_num="$(next_ready_issue_number)"
        if [ -z "$issue_num" ]; then skipped="${skipped} ready issue番号なし"; continue; fi
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
            skipped="${skipped} 修正対象外:${name}"
            continue
          fi
        else
          pr_num="$(jq -r '.[0] // ""' <<< "$fix_candidates")"
        fi
        if [ -z "$pr_num" ]; then skipped="${skipped} 修正可能なレビュー指摘なし"; continue; fi
        name="fix-review-pr-${pr_num}"
        ;;
      review)
        pr_num=""
        local review_candidates
        review_candidates="$(review_pr_numbers_json)"
        if [[ "$name" =~ ^review-pr-([0-9]+)$ ]]; then
          pr_num="${BASH_REMATCH[1]}"
          if ! json_has_number "$pr_num" "$review_candidates"; then
            skipped="${skipped} レビュー対象外:${name}"
            continue
          fi
        else
          pr_num="$(jq -r '.[0] // ""' <<< "$review_candidates")"
        fi
        if [ -z "$pr_num" ]; then skipped="${skipped} レビュー対象PRなし"; continue; fi
        name="review-pr-${pr_num}"
        ;;
      e2e)
        if ! role_active "dev-server"; then skipped="${skipped} dev-server未起動"; continue; fi
        ;;
      e2e-bug-hunt)
        if ! role_active "dev-server"; then skipped="${skipped} dev-server未起動"; continue; fi
        if ! post_merge_due; then skipped="${skipped} 新規mergeなし"; continue; fi
        ;;
      ui-audit)
        if [ "$AUTO_UI_AUDIT" != "true" ]; then skipped="${skipped} ui-audit自動起動なし"; continue; fi
        if ! role_active "dev-server"; then skipped="${skipped} dev-server未起動"; continue; fi
        if ! post_merge_due; then skipped="${skipped} 新規mergeなし"; continue; fi
        ;;
      watch-main)
        if ! role_active "dev-server"; then skipped="${skipped} dev-server未起動"; continue; fi
        if [ "$AUTO_WATCH_MAIN" != "true" ] || ! post_merge_due; then
          skipped="${skipped} watch-main条件未成立"
          continue
        fi
        ;;
      improve)
        if [ "$AUTO_IMPROVE" != "true" ] || [ "${ISSUES:-0}" -ne 0 ]; then
          skipped="${skipped} improve条件未成立"
          continue
        fi
        ;;
    esac
    [ -n "$name" ] && [ "$name" != "null" ] || name="$role"
    if pane_name_active "$name"; then
      skipped="${skipped} 既に起動:${name}"
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
      skipped="${skipped} 起動失敗:${name}"
    fi
  done < <(jq -r '.actions[]? | [.role, (.name // .role), (.reason // "")] | @tsv' <<< "$plan" 2>/dev/null)

  if jq -e '.actions[]? | .role == "e2e" or .role == "e2e-bug-hunt" or .role == "ui-audit" or .role == "watch-main" or .role == "improve"' >/dev/null 2>&1 <<< "$plan"; then
    [ "$launched" -gt 0 ] && mark_post_merge_spawned
  fi

  if [ "$changed" -gt 0 ]; then
    record_decision "ai" "変更:${launched_roles# }" "見送り:${skipped# }"
    return 0
  fi

  local skip_reasons
  skip_reasons=$(jq -r '[.skip[]? | .role + ":" + .reason] | join(" | ")' <<< "$plan" 2>/dev/null)
  [ -n "$skip_reasons" ] && [ "$skip_reasons" != "null" ] || skip_reasons="見送り:${skipped# }"
  record_decision "ai" "pane作成なし" "$skip_reasons"
  return 1
}

fallback_scale() {
  local cur_impl; cur_impl=$(count_alive "implement")
  local cur_review; cur_review=$(count_alive "review")
  local cur_fix;  cur_fix=$(count_alive "fix-review")
  local cur_e2e;  cur_e2e=$(count_alive "e2e-bug-hunt")
  local cur_ui;   cur_ui=$(count_alive "ui-audit")
  local cur_watch=0 cur_imp=0 issue_num pr_num
  local launched=""
  [ "$AUTO_WATCH_MAIN" = "true" ] && cur_watch=$(count_alive "watch-main")
  [ "$AUTO_IMPROVE" = "true" ] && cur_imp=$(count_alive "improve")

  local desired=0
  if [ "$AUTO_DEV_SERVER" = "true" ] && has_dev_target && ! role_active "dev-server" && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    if add_pane "dev-server" "dev-server" "" "開発サーバー対象があり、dev-server pane が未起動のため作成する。"; then
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
    if add_pane "$impl_name" "implement" "$(implement_context_for_issue "$issue_num")" "ready issue #${issue_num} があり、依存待ちではないため実装 pane を作成する。"; then
      launched="${launched} ${impl_name}"
      cur_impl=$((cur_impl + 1))
    else
      break
    fi
  done

  pr_num="$(next_review_pr_number)"
  if [ -n "$pr_num" ] && [ "$cur_review" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    if add_pane "review-pr-${pr_num}" "review" "$(review_context_for_pr "$pr_num")" "PR #${pr_num} がレビューまたはマージ判断待ちのため review pane を作成する。"; then
      launched="${launched} review-pr-${pr_num}"
    fi
  fi

  local desired_fix=0
  desired_fix="$(fix_review_pr_numbers_json | jq 'length')"
  if [ "$MAX_FIX_REVIEW" -gt 0 ] && [ "$MAX_FIX_REVIEW" -lt "$desired_fix" ]; then
    desired_fix="$MAX_FIX_REVIEW"
  fi
  while [ "$cur_fix" -lt "$desired_fix" ] && below_limit "$(total_alive)" "$MAX_ALIVE"; do
    pr_num="$(next_fix_review_pr_number)"
    [ -n "$pr_num" ] || break
    if add_pane "fix-review-pr-${pr_num}" "fix-review" "$(fix_review_context_for_pr "$pr_num")" "PR #${pr_num} に対応可能な requested changes があるため fix-review pane を作成する。"; then
      launched="${launched} fix-review-pr-${pr_num}"
      cur_fix=$((cur_fix + 1))
    else
      break
    fi
  done

  if post_merge_due && role_active "dev-server" && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    if [ "$cur_e2e" -eq 0 ]; then
      if add_pane "e2e-hunt" "e2e-bug-hunt" "" "新しい merge を検出し、dev-server が稼働中のため E2E bug hunt pane を作成する。"; then
        launched="${launched} e2e-hunt"
      fi
    fi
    if [ "$AUTO_UI_AUDIT" = "true" ] && [ "$cur_ui" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
      if add_pane "ui-audit" "ui-audit" "" "新しい merge を検出し、良いデザイン品質を守るため UI/UX audit pane を作成する。"; then
        launched="${launched} ui-audit"
      fi
    fi
    if [ "$AUTO_WATCH_MAIN" = "true" ] && [ "$cur_watch" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
      if add_pane "watch-main" "watch-main" "" "merge 後監視が有効なため watch-main pane を作成する。"; then
        launched="${launched} watch-main"
      fi
    fi
    if [ "$AUTO_IMPROVE" = "true" ] && [ "$cur_imp" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
      if add_pane "improve" "improve" "" "実装 work が空で improve 自動起動が有効なため improve pane を作成する。"; then
        launched="${launched} improve"
      fi
    fi
    [ -n "$launched" ] && mark_post_merge_spawned
  fi

  # Issue が 0 件なら feature-discovery を起動して新機能を提案→issue作成
  if [ "${ISSUES:-0}" -eq 0 ] && ! role_active "feature-discovery" && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    if add_pane "feature-discovery" "feature-discovery" "" "オープン issue が 0 件のため、新機能を調査して issue を作成する。"; then
      launched="${launched} feature-discovery"
    fi
  fi

  if [ -n "$launched" ]; then
    record_decision "fallback" "作成:${launched# }" "安全側の fallback ルールに一致したため pane を作成した。"
  else
    local idle_detail=""
    if [ "$AUTO_DEV_SERVER" != "true" ]; then
      idle_detail="${idle_detail} dev-server 自動起動が無効;"
    elif ! has_dev_target; then
      idle_detail="${idle_detail} 開発サーバー対象なし;"
    elif role_active "dev-server"; then
      idle_detail="${idle_detail} dev-server は既に稼働中;"
    else
      idle_detail="${idle_detail} dev-server 作成不要;"
    fi
    [ "${READY_ISSUES:-0}" -le 0 ] && idle_detail="${idle_detail} ready issue なし;"
    [ -z "$(next_review_pr_number)" ] && idle_detail="${idle_detail} レビュー対象 PR なし;"
    [ -z "$(next_fix_review_pr_number)" ] && idle_detail="${idle_detail} 対応可能な requested changes なし;"
    if ! post_merge_due; then
      idle_detail="${idle_detail} 新規 merge 後作業なし;"
    elif ! role_active "dev-server"; then
      idle_detail="${idle_detail} merge 後作業は dev-server 待ち;"
    fi
    record_decision "fallback" "待機" "${idle_detail# }"
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
