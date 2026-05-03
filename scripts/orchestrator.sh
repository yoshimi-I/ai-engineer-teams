#!/usr/bin/env bash
# Orchestrator: manages all agent panes, displays status, scales as needed
set -uo pipefail

export GIT_EDITOR=true
export EDITOR=true

PROJECT_CWD="$(pwd)"
STATUS_DIR=".agent-status"
CACHE_DIR="${STATUS_DIR}/.cache"
CACHE_TTL=25
PANE_REGISTRY="${STATUS_DIR}/.panes"
GH_REFRESH=60
TICK_INTERVAL="${ORCH_TICK_INTERVAL:-10}"
POST_MERGE_STATE="${STATUS_DIR}/.last_post_merge_pr"
PIPELINE_TAB_ID=""
MAX_ALIVE="${ORCH_MAX_ALIVE:-0}"
MAX_IMPLEMENT="${ORCH_MAX_IMPLEMENT:-0}"
AUTO_WATCH_MAIN="${ORCH_AUTO_WATCH_MAIN:-false}"
AUTO_IMPROVE="${ORCH_AUTO_IMPROVE:-false}"
AUTO_DEV_SERVER="${ORCH_AUTO_DEV_SERVER:-true}"
AI_ORCHESTRATION="${ORCH_AI:-true}"
AI_PLAN_PROMPT=".kiro/prompts/orchestrator-plan.md"
AI_PLAN_FILE="${CACHE_DIR}/orchestrator_plan.json"
DECISION_FILE="${CACHE_DIR}/orchestrator_decision.json"
ORCH_STATUS_FILE="${STATUS_DIR}/orchestrator.json"
DEV_HEALTH_FILE="${STATUS_DIR}/dev-server-health.json"
LAST_DECISION_SUMMARY="booting"
LAST_DECISION_DETAIL="initializing"
LAST_DECISION_TS=""
LAST_PLAN_SOURCE="none"

mkdir -p "$STATUS_DIR" "$CACHE_DIR"
touch "$PANE_REGISTRY"

# ── GitHub API ──

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
  PRS_JSON=$(gh_cached prs_json gh pr list --limit 30 --json number,title,headRefName,reviewDecision,author)
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
  LATEST_MERGED_PR=$(gh_cached latest_merged_pr gh pr list --state merged --limit 1 --json number \
    --jq '.[0].number // ""')
  HAS_MERGES=false
  [ -n "${LATEST_MERGED_PR:-}" ] && HAS_MERGES=true
}

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
      latest_merged_pr: $latest_merged_pr
    }' > "$DECISION_FILE"
  write_orchestrator_status "🧠 deciding" "$summary"
}

# ── Pane management ──

pane_number() {
  local pane="$1"
  echo "${pane#terminal_}"
}

resolve_pipeline_tab_id() {
  if [ -n "$PIPELINE_TAB_ID" ]; then
    return
  fi

  if [ -n "${ZELLIJ_PANE_ID:-}" ]; then
    local current_id
    current_id=$(pane_number "$ZELLIJ_PANE_ID")
    PIPELINE_TAB_ID=$(zellij action list-panes --json 2>/dev/null \
      | jq -r --argjson id "$current_id" '.[] | select(.id == $id) | .tab_id' 2>/dev/null \
      | head -n 1)
  fi

  if [ -z "$PIPELINE_TAB_ID" ] || [ "$PIPELINE_TAB_ID" = "null" ]; then
    PIPELINE_TAB_ID=$(zellij action list-tabs --json 2>/dev/null \
      | jq -r '.[] | select(.name == "Pipeline") | .tab_id' 2>/dev/null \
      | head -n 1)
  fi
}

pane_exists() {
  local pane="$1"
  local id
  id=$(pane_number "$pane")
  zellij action list-panes --json 2>/dev/null \
    | jq -e --argjson id "$id" '.[] | select(.id == $id and (.exited | not))' >/dev/null 2>&1
}

pane_name_expr='.name // .pane_name // .title // .command // ""'

zellij_panes_json() {
  zellij action list-panes --json 2>/dev/null || echo "[]"
}

role_from_name() {
  case "$1" in
    dev-server) echo "dev-server" ;;
    review) echo "review" ;;
    fix-review) echo "fix-review" ;;
    e2e) echo "e2e" ;;
    e2e-hunt) echo "e2e-bug-hunt" ;;
    watch-main) echo "watch-main" ;;
    improve) echo "improve" ;;
    implement-*) echo "implement" ;;
    *) echo "" ;;
  esac
}

record_registry_entry() {
  local name="$1" role="$2" pane="$3" status="${4:-alive}"
  grep -v "^${name}|" "$PANE_REGISTRY" > "${PANE_REGISTRY}.tmp" 2>/dev/null || true
  mv "${PANE_REGISTRY}.tmp" "$PANE_REGISTRY"
  echo "${name}|${role}|${pane}|${status}" >> "$PANE_REGISTRY"
}

adopt_existing_panes() {
  local panes name id role pane reg_name existing_pane
  panes=$(zellij_panes_json)
  while IFS=$'\t' read -r name id; do
    [ -n "$name" ] || continue
    [ -n "$id" ] || continue
    role=$(role_from_name "$name")
    [ -n "$role" ] || continue
    pane="terminal_${id}"
    reg_name="$name"
    existing_pane=$(awk -F'|' -v agent="$reg_name" '$1 == agent { print $3; exit }' "$PANE_REGISTRY")
    if [ -n "$existing_pane" ] && [ "$existing_pane" != "$pane" ]; then
      reg_name="${name}-${id}"
    fi
    record_registry_entry "$reg_name" "$role" "$pane" "alive"
  done < <(jq -r '.[] | select(.exited | not) | [('"$pane_name_expr"'), (.id | tostring)] | @tsv' <<< "$panes" 2>/dev/null)
}

singleton_role() {
  case "$1" in
    dev-server|review|fix-review|e2e|e2e-bug-hunt|watch-main|improve) return 0 ;;
    *) return 1 ;;
  esac
}

dedupe_singleton_role() {
  local role="$1" seen="" tmp="${PANE_REGISTRY}.tmp"
  : > "$tmp"
  while IFS='|' read -r name r pane status; do
    [ -z "$name" ] && continue
    if [ "$r" = "$role" ] && [ "$status" = "alive" ]; then
      if [ -z "$seen" ]; then
        seen="$name"
        echo "${name}|${r}|${pane}|${status}" >> "$tmp"
      else
        zellij action close-pane --pane-id "$pane" 2>/dev/null || true
        cat > "${STATUS_DIR}/${name}.json" <<JSON
{"agent":"${name}","prompt":"${role}","state":"⏹️ stopped","detail":"deduplicated singleton role","issue":"","pr":"","branch":"","cycle":0,"errors":0,"ts":"$(date '+%H:%M:%S')"}
JSON
      fi
    else
      echo "${name}|${r}|${pane}|${status}" >> "$tmp"
    fi
  done < "$PANE_REGISTRY"
  mv "$tmp" "$PANE_REGISTRY"
}

count_alive() {
  local role="$1" count=0
  while IFS='|' read -r name r _pane status; do
    [ -z "$name" ] && continue
    [ "$r" = "$role" ] && [ "$status" = "alive" ] && count=$((count + 1))
  done < "$PANE_REGISTRY"
  echo $count
}

update_pane_status() {
  adopt_existing_panes
  local tmp="${PANE_REGISTRY}.tmp"; : > "$tmp"
  local now; now=$(date +%s)
  while IFS='|' read -r name role pane status; do
    [ -z "$name" ] && continue
    if ! pane_exists "$pane"; then
      continue
    fi
    local mtime=0
    [ -f "${STATUS_DIR}/${name}.json" ] && mtime=$(stat -f%m "${STATUS_DIR}/${name}.json" 2>/dev/null || stat -c%Y "${STATUS_DIR}/${name}.json" 2>/dev/null || echo 0)
    if [ $((now - mtime)) -lt 300 ]; then
      echo "${name}|${role}|${pane}|alive" >> "$tmp"
    else
      echo "${name}|${role}|${pane}|stopped" >> "$tmp"
    fi
  done < "$PANE_REGISTRY"
  mv "$tmp" "$PANE_REGISTRY"
  dedupe_singleton_role "dev-server"
  check_dev_server_health
}

add_pane() {
  local name="$1" role="$2"
  adopt_existing_panes
  if singleton_role "$role"; then
    dedupe_singleton_role "$role"
    while IFS='|' read -r n r _pane s; do
      [ "$r" = "$role" ] && [ "$s" = "alive" ] && return
    done < "$PANE_REGISTRY"
  fi
  # Skip if already exists and alive
  while IFS='|' read -r n r _pane s; do
    [ "$n" = "$name" ] && [ "$s" = "alive" ] && return
  done < "$PANE_REGISTRY"

  # Remove old stopped entry with same name
  grep -v "^${name}|" "$PANE_REGISTRY" > "${PANE_REGISTRY}.tmp" 2>/dev/null || true
  mv "${PANE_REGISTRY}.tmp" "$PANE_REGISTRY"

  cat > "${STATUS_DIR}/${name}.json" <<JSON
{"agent":"${name}","prompt":"${role}","state":"🚀 starting","detail":"","issue":"","pr":"","branch":"","cycle":0,"errors":0,"ts":"$(date '+%H:%M:%S')"}
JSON
  resolve_pipeline_tab_id
  local pane
  if [ -n "$PIPELINE_TAB_ID" ] && [ "$PIPELINE_TAB_ID" != "null" ]; then
    pane=$(zellij action new-pane --tab-id "$PIPELINE_TAB_ID" --name "$name" --cwd "$PROJECT_CWD" --close-on-exit \
      -- bash -lc "AGENT_ID='${name}' AGENT_ONCE=true AGENT_INTERVAL=30 ./scripts/agent.sh '${role}'")
  else
    pane=$(zellij action new-pane --name "$name" --cwd "$PROJECT_CWD" --close-on-exit \
      -- bash -lc "AGENT_ID='${name}' AGENT_ONCE=true AGENT_INTERVAL=30 ./scripts/agent.sh '${role}'")
  fi
  record_registry_entry "$name" "$role" "$pane" "alive"
}

kill_role() {
  local role="$1"
  local tmp="${PANE_REGISTRY}.tmp"; : > "$tmp"
  while IFS='|' read -r name r pane status; do
    [ -z "$name" ] && continue
    if [ "$r" = "$role" ] && [ "$status" = "alive" ]; then
      zellij action close-pane --pane-id "$pane" 2>/dev/null || true
      cat > "${STATUS_DIR}/${name}.json" <<JSON
{"agent":"${name}","prompt":"${role}","state":"⏹️ stopped","detail":"no longer needed","issue":"","pr":"","branch":"","cycle":0,"errors":0,"ts":"$(date '+%H:%M:%S')"}
JSON
    else
      echo "${name}|${r}|${pane}|${status}" >> "$tmp"
    fi
  done < "$PANE_REGISTRY"
  mv "$tmp" "$PANE_REGISTRY"
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

total_alive() {
  grep -c "|alive$" "$PANE_REGISTRY" 2>/dev/null || true
}

has_dev_target() {
  [ -f "justfile" ] && grep -Eq '^[[:space:]]*dev:' justfile && return 0
  [ -f "package.json" ] && return 0
  [ -f "pyproject.toml" ] && return 0
  [ -f "Cargo.toml" ] && return 0
  [ -f "go.mod" ] && return 0
  return 1
}

candidate_dev_urls() {
  {
    grep -Eho 'https?://(localhost|127\.0\.0\.1):[0-9]+' .agent-logs/dev-server.log 2>/dev/null || true
    printf '%s\n' \
      "http://localhost:5173" \
      "http://localhost:3000" \
      "http://localhost:4173" \
      "http://localhost:8000" \
      "http://localhost:8080"
  } | awk '!seen[$0]++'
}

check_dev_server_health() {
  local url healthy_url="" pane_count
  pane_count=$(count_alive "dev-server")
  while IFS= read -r url; do
    [ -n "$url" ] || continue
    if curl -fsS --max-time 1 "$url" >/dev/null 2>&1; then
      healthy_url="$url"
      break
    fi
  done < <(candidate_dev_urls)

  jq -n \
    --argjson pane_count "$pane_count" \
    --arg url "$healthy_url" \
    --arg ts "$(date '+%H:%M:%S')" \
    '{
      pane_count: $pane_count,
      healthy: ($url != ""),
      url: $url,
      ts: $ts
    }' > "$DEV_HEALTH_FILE"
}

dev_health_json() {
  if [ -f "$DEV_HEALTH_FILE" ]; then
    cat "$DEV_HEALTH_FILE"
  else
    jq -n '{pane_count: 0, healthy: false, url: "", ts: ""}'
  fi
}

limit_reached() {
  local current="$1" max="$2"
  [ "$max" -gt 0 ] && [ "$current" -ge "$max" ]
}

below_limit() {
  ! limit_reached "$1" "$2"
}

active_panes_json() {
  jq -Rn '
    [inputs
      | select(length > 0)
      | split("|")
      | select(length >= 4)
      | {name: .[0], role: .[1], pane: .[2], status: .[3]}]
  ' < "$PANE_REGISTRY"
}

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
    --argjson max_alive "$MAX_ALIVE" \
    --argjson max_implement "$MAX_IMPLEMENT" \
    --arg next_implement "$(next_implement_name)" \
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
      active_panes: $active,
      issues: {
        unassigned_count: ([$issues[] | select(.assignees | length == 0)] | length),
        ready_count: (
          [$issues[].number] as $open
          | [$issues[] | select(.assignees | length == 0)
            | select(([.labels[]?.name] | index("blocked") | not))
            | select(((.body // "" | [scan("depends-on: *#([0-9]+)") | .[0] | tonumber]) as $deps
              | ([$deps[] | select(. as $d | $open | index($d))] | length) == 0))]
          | length
        ),
        open: $issues
      },
      pull_requests: {
        changes_requested_count: ([$prs[] | select(.reviewDecision == "CHANGES_REQUESTED")] | length),
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

role_active() {
  local role="$1"
  [ "$(count_alive "$role")" -gt 0 ]
}

valid_role() {
  case "$1" in
    dev-server|implement|review|fix-review|e2e|e2e-bug-hunt|watch-main|improve) return 0 ;;
    *) return 1 ;;
  esac
}

execute_ai_plan() {
  local plan="$1" changed=0 launched=0 launched_implement=0 launched_roles="" skipped=""
  while IFS=$'\t' read -r role; do
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
      launched_roles="${launched_roles} stopped-${role}"
    fi
  done < <(jq -r '.stop[]? | .role' <<< "$plan" 2>/dev/null)

  while IFS=$'\t' read -r role name; do
    if ! valid_role "$role"; then
      skipped="${skipped} invalid:${role}"
      continue
    fi
    if limit_reached "$(total_alive)" "$MAX_ALIVE"; then
      skipped="${skipped} max-alive"
      break
    fi
    if [ "$role" != "implement" ] && role_active "$role"; then
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
        name="$(next_implement_name)"
        launched_implement=$((launched_implement + 1))
        ;;
      fix-review)
        if [ "${CHANGES_REQ:-0}" -le 0 ]; then skipped="${skipped} no-review-changes"; continue; fi
        ;;
      review)
        if [ "$(jq '[.[] | select(.reviewDecision != "CHANGES_REQUESTED")] | length' <<< "${PRS_JSON:-[]}" 2>/dev/null || echo 0)" -le 0 ]; then skipped="${skipped} no-reviewable-pr"; continue; fi
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
    add_pane "$name" "$role"
    changed=$((changed + 1))
    launched=$((launched + 1))
    launched_roles="${launched_roles} ${name}:${role}"
  done < <(jq -r '.actions[]? | [.role, (.name // .role)] | @tsv' <<< "$plan" 2>/dev/null)

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
  local cur_fix;  cur_fix=$(count_alive "fix-review")
  local cur_e2e;  cur_e2e=$(count_alive "e2e-bug-hunt")
  local cur_watch=0 cur_imp=0
  local launched=""
  [ "$AUTO_WATCH_MAIN" = "true" ] && cur_watch=$(count_alive "watch-main")
  [ "$AUTO_IMPROVE" = "true" ] && cur_imp=$(count_alive "improve")

  local desired=0
  if [ "$AUTO_DEV_SERVER" = "true" ] && has_dev_target && ! role_active "dev-server" && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    add_pane "dev-server" "dev-server"
    launched="${launched} dev-server"
  fi

  if [ "${READY_ISSUES:-0}" -gt 0 ]; then
    desired="$READY_ISSUES"
    if [ "$MAX_IMPLEMENT" -gt 0 ] && [ "$MAX_IMPLEMENT" -lt "$desired" ]; then
      desired="$MAX_IMPLEMENT"
    fi
  fi
  while [ "$cur_impl" -lt "$desired" ] && below_limit "$(total_alive)" "$MAX_ALIVE"; do
    local impl_name
    impl_name="$(next_implement_name)"
    add_pane "$impl_name" "implement"
    launched="${launched} ${impl_name}"
    cur_impl=$((cur_impl + 1))
  done

  if [ "${CHANGES_REQ:-0}" -gt 0 ] && [ "$cur_fix" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    add_pane "fix-review" "fix-review"
    launched="${launched} fix-review"
  fi

  if post_merge_due && role_active "dev-server" && below_limit "$(total_alive)" "$MAX_ALIVE"; then
    if [ "$cur_e2e" -eq 0 ]; then
      add_pane "e2e-hunt" "e2e-bug-hunt"
      launched="${launched} e2e-hunt"
    fi
    if [ "$AUTO_WATCH_MAIN" = "true" ] && [ "$cur_watch" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
      add_pane "watch-main" "watch-main"
      launched="${launched} watch-main"
    fi
    if [ "$AUTO_IMPROVE" = "true" ] && [ "$cur_imp" -eq 0 ] && below_limit "$(total_alive)" "$MAX_ALIVE"; then
      add_pane "improve" "improve"
      launched="${launched} improve"
    fi
    [ -n "$launched" ] && mark_post_merge_spawned
  fi

  if [ -n "$launched" ]; then
    record_decision "fallback" "launched:${launched# }" "conservative rule matched"
  else
    record_decision "fallback" "idle" "no rule matched"
  fi
}

# ── Display ──

render() {
  clear
  echo -e "\033[1m\033[36m"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║            🎭  O R C H E S T R A T O R  🎭                ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  echo -e "\033[0m"

  local alive; alive=$(total_alive)
  local total; total=$(wc -l < "$PANE_REGISTRY" | tr -d ' ')
  echo -e "  \033[2m$(date '+%H:%M:%S')\033[0m  \033[32m▶ ${alive} 稼働\033[0m / ${total} 合計  📋 ready: \033[33m${READY_ISSUES:-?}\033[0m / open: \033[33m${ISSUES:-?}\033[0m  🔧 要修正: \033[31m${CHANGES_REQ:-?}\033[0m  🔀 merge: $(if ${HAS_MERGES:-false}; then echo -e '\033[32m✓\033[0m'; else echo -e '\033[2m-\033[0m'; fi)"
  if [ -f "$DEV_HEALTH_FILE" ]; then
    local dev_ok dev_url dev_panes
    dev_ok=$(jq -r '.healthy // false' "$DEV_HEALTH_FILE" 2>/dev/null || echo false)
    dev_url=$(jq -r '.url // ""' "$DEV_HEALTH_FILE" 2>/dev/null || echo "")
    dev_panes=$(jq -r '.pane_count // 0' "$DEV_HEALTH_FILE" 2>/dev/null || echo 0)
    if [ "$dev_ok" = "true" ]; then
      echo -e "  🖥️  dev-server: \033[32mhealthy\033[0m ${dev_url}  panes:${dev_panes}"
    else
      echo -e "  🖥️  dev-server: \033[33mnot ready\033[0m  panes:${dev_panes}"
    fi
  fi
  echo -e "  \033[35m🧠 ${LAST_PLAN_SOURCE}\033[0m  ${LAST_DECISION_SUMMARY}  \033[2m${LAST_DECISION_DETAIL} (${LAST_DECISION_TS:---:--:--}) next:${TICK_INTERVAL}s\033[0m"
  echo ""

  # Table header
  printf "  \033[2m┌──────────────────────┬──────────────┬────────┬────────────────────────────────────────────────────────┐\033[0m\n"
  printf "  \033[2m│\033[0m \033[1m%-20s\033[0m \033[2m│\033[0m \033[1m%-12s\033[0m \033[2m│\033[0m \033[1m%-6s\033[0m \033[2m│\033[0m \033[1m%-54s\033[0m \033[2m│\033[0m\n" "Name" "Role" "State" "Detail"
  printf "  \033[2m├──────────────────────┼──────────────┼────────┼────────────────────────────────────────────────────────┤\033[0m\n"

  while IFS='|' read -r name role _pane status; do
    [ -z "$name" ] && continue

    local state_str="" issue_str="" pr_str="" branch_str="" detail=""
    if [ -f "${STATUS_DIR}/${name}.json" ]; then
      state_str=$(jq -r '.state // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
      issue_str=$(jq -r '.issue // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
      pr_str=$(jq -r '.pr // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
      branch_str=$(jq -r '.branch // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
      detail=$(jq -r '.detail // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
    fi

    # Build rich detail string
    local rich_detail=""
    [ -n "$state_str" ] && rich_detail="${state_str}"
    [ -n "$issue_str" ] && rich_detail="${rich_detail} 📋${issue_str}"
    [ -n "$pr_str" ] && rich_detail="${rich_detail} 🔗${pr_str}"
    [ -n "$branch_str" ] && rich_detail="${rich_detail} 🌿${branch_str}"
    [ -n "$detail" ] && [ "$detail" != "$state_str" ] && rich_detail="${rich_detail} ${detail}"
    [ ${#rich_detail} -gt 52 ] && rich_detail="${rich_detail:0:51}…"

    local state_icon
    if [ "$status" = "alive" ]; then
      state_icon="\033[32m● 稼働\033[0m"
    else
      state_icon="\033[31m○ 停止\033[0m"
    fi

    local color
    case "$role" in
      implement)    color="\033[33m" ;;
      fix-review)   color="\033[31m" ;;
      dev-server)   color="\033[32m" ;;
      watch-main)   color="\033[35m" ;;
      e2e)           color="\033[36m" ;;
      e2e-bug-hunt) color="\033[36m" ;;
      improve)      color="\033[34m" ;;
      *)            color="\033[2m" ;;
    esac

    printf "  \033[2m│\033[0m ${color}%-20s\033[0m \033[2m│\033[0m %-12s \033[2m│\033[0m ${state_icon} \033[2m│\033[0m %-54s \033[2m│\033[0m\n" "$name" "$role" "" "$rich_detail"
  done < "$PANE_REGISTRY"

  if [ "$(wc -l < "$PANE_REGISTRY" | tr -d ' ')" -eq 0 ]; then
    printf "  \033[2m│ %-20s │ %-12s │ %-6s │ %-54s │\033[0m\n" "(起動中...)" "" "" ""
  fi
  printf "  \033[2m└──────────────────────┴──────────────┴────────┴────────────────────────────────────────────────────────┘\033[0m\n"
  echo ""

  # ── Work Summary ──
  # Show assigned issues and open PRs
  local summary_file="${CACHE_DIR}/work_summary"
  local summary_age=999
  [ -f "$summary_file" ] && summary_age=$(( $(date +%s) - $(stat -f%m "$summary_file" 2>/dev/null || stat -c%Y "$summary_file" 2>/dev/null || echo 0) ))

  if [ $summary_age -ge $CACHE_TTL ]; then
    {
      echo "ISSUES_IN_PROGRESS:"
      gh issue list --state open --json number,title,assignees \
        --jq '.[] | select(.assignees | length > 0) | "  #\(.number) \(.title) ← \(.assignees[0].login)"' 2>/dev/null || true
      echo "OPEN_PRS:"
      gh pr list --json number,title,headRefName,reviewDecision \
        --jq '.[] | "  #\(.number) [\(.reviewDecision // "PENDING")] \(.title) (\(.headRefName))"' 2>/dev/null || true
    } > "$summary_file" 2>/dev/null || true
  fi

  if [ -f "$summary_file" ]; then
    echo -e "  \033[1m📋 Current Work\033[0m"
    while IFS= read -r line; do
      case "$line" in
        "ISSUES_IN_PROGRESS:") echo -e "  \033[33mIssues (着手中):\033[0m" ;;
        "OPEN_PRS:") echo -e "  \033[36mPull Requests:\033[0m" ;;
        *)
          [ -n "$line" ] && echo -e "  \033[2m${line}\033[0m"
          ;;
      esac
    done < "$summary_file"
    echo ""
  fi

  if [ -f "$AI_PLAN_FILE" ]; then
    echo -e "  \033[1m🧠 Last AI Plan\033[0m"
    local actions skips
    actions=$(jq -r '[.actions[]? | (.name // .role) + ":" + .role] | join(", ")' "$AI_PLAN_FILE" 2>/dev/null)
    stops=$(jq -r '[.stop[]? | .role] | join(", ")' "$AI_PLAN_FILE" 2>/dev/null)
    skips=$(jq -r '[.skip[]? | .role + ":" + .reason] | join(" | ")' "$AI_PLAN_FILE" 2>/dev/null)
    [ -n "$actions" ] && [ "$actions" != "null" ] || actions="none"
    [ -n "$stops" ] && [ "$stops" != "null" ] || stops="none"
    [ -n "$skips" ] && [ "$skips" != "null" ] || skips="none"
    echo -e "  \033[32mActions:\033[0m \033[2m${actions}\033[0m"
    echo -e "  \033[31mStops:\033[0m \033[2m${stops}\033[0m"
    echo -e "  \033[33mSkipped:\033[0m \033[2m${skips:0:140}\033[0m"
    echo ""
  fi
}

# ── Scaling ──

scale() {
  update_pane_status
  local alive; alive=$(total_alive)

  # Let the AI planner decide pane count. Bash only enforces hard safety limits.
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

# ── Main ──

ISSUES=0; READY_ISSUES=0; CHANGES_REQ=0; HAS_MERGES=false; LATEST_MERGED_PR=""; last_gh=0

write_orchestrator_status "🚀 starting" "initializing orchestrator"
refresh_github

# Initial scale — immediately spawn agents based on current issues
scale
render

while true; do
  sleep "$TICK_INTERVAL"

  now=$(date +%s)
  [ $((now - last_gh)) -ge $GH_REFRESH ] && refresh_github && last_gh=$now

  scale
  update_pane_status
  write_orchestrator_status "🟢 watching" "$LAST_DECISION_SUMMARY"
  render
done
