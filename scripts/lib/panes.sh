#!/usr/bin/env bash

# write_pane_status_file <path> <agent> <prompt> <state> <detail> [pr] [issue] [branch] [cycle] [errors] [epoch]
# Atomically writes an agent status JSON. All non-path args default to sensible
# empty values so callers can pass only what they have. Uses atomic_write_json
# from common.sh so concurrent readers never see partial files.
write_pane_status_file() {
  local path="$1" agent="$2" prompt="$3" state="$4" detail="${5:-}"
  local pr="${6:-}" issue="${7:-}" branch="${8:-}"
  local cycle="${9:-0}" errors="${10:-0}" epoch="${11:-}"
  local ts
  ts=$(date '+%H:%M:%S')
  [ -z "$epoch" ] && epoch=$(date +%s)
  # shellcheck disable=SC2016
  atomic_write_json "$path" \
    '{
      agent: $agent,
      prompt: $prompt,
      state: $state,
      detail: $detail,
      issue: $issue,
      pr: $pr,
      branch: $branch,
      cycle: $cycle,
      errors: $errors,
      ts: $ts,
      epoch: $epoch
    }' \
    --arg agent "$agent" \
    --arg prompt "$prompt" \
    --arg state "$state" \
    --arg detail "$detail" \
    --arg issue "$issue" \
    --arg pr "$pr" \
    --arg branch "$branch" \
    --argjson cycle "$cycle" \
    --argjson errors "$errors" \
    --arg ts "$ts" \
    --argjson epoch "$epoch"
}

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

resolve_agents_tab_id() {
  if [ -n "$AGENTS_TAB_ID" ]; then
    return
  fi

  AGENTS_TAB_ID=$(zellij action list-tabs --json 2>/dev/null \
    | jq -r '.[] | select(.name == "Agents") | .tab_id' 2>/dev/null \
    | head -n 1)

  if [ -z "$AGENTS_TAB_ID" ] || [ "$AGENTS_TAB_ID" = "null" ]; then
    resolve_pipeline_tab_id
    AGENTS_TAB_ID=$(zellij action new-tab --name "Agents" --cwd "$PROJECT_CWD" \
      -- bash -lc "echo 'Agent panes will be created here by the orchestrator.'; while true; do sleep 3600; done" 2>/dev/null || true)
    if [ -n "$PIPELINE_TAB_ID" ] && [ "$PIPELINE_TAB_ID" != "null" ]; then
      zellij action go-to-tab-by-id "$PIPELINE_TAB_ID" 2>/dev/null || true
    fi
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

close_agent_placeholder_panes() {
  zellij_panes_json \
    | jq -r '
        .[]
        | select(.exited | not)
        | select(('"$pane_name_expr"') == "agent-placeholder" or ('"$pane_name_expr"') == "Agent Area")
        | "terminal_\(.id)"
      ' 2>/dev/null \
    | while IFS= read -r placeholder_pane; do
        [ -n "$placeholder_pane" ] || continue
        zellij action close-pane --pane-id "$placeholder_pane" 2>/dev/null || true
      done
}

registry_tmp() {
  mktemp "${PANE_REGISTRY}.XXXXXX"
}

agent_arg_b64() {
  printf '%s' "$1" | base64 | tr -d '\n'
}

pane_current_name() {
  local pane="$1" id
  id=$(pane_number "$pane")
  zellij_panes_json \
    | jq -r --argjson id "$id" '.[] | select(.id == $id and (.exited | not)) | ('"$pane_name_expr"')' 2>/dev/null \
    | head -n 1
}

role_from_name() {
  case "$1" in
    dev-server) echo "dev-server" ;;
    review|review-pr-*) echo "review" ;;
    fix-review|fix-review-pr-*) echo "fix-review" ;;
    e2e) echo "e2e" ;;
    e2e-hunt) echo "e2e-bug-hunt" ;;
    ui-audit) echo "ui-audit" ;;
    watch-main) echo "watch-main" ;;
    improve) echo "improve" ;;
    feature-discovery) echo "feature-discovery" ;;
    create-issue) echo "create-issue" ;;
    implement-*) echo "implement" ;;
    *) echo "" ;;
  esac
}

record_registry_entry() {
  local name="$1" role="$2" pane="$3" status="${4:-alive}"
  if [ -z "$name" ]; then
    case "$role" in
      dev-server|e2e|watch-main|improve|ui-audit) name="$role" ;;
      review) name="review" ;;
      fix-review) name="fix-review" ;;
      e2e-bug-hunt) name="e2e-hunt" ;;
      implement) name="$(next_implement_name)" ;;
      *) name="unknown-${pane#terminal_}" ;;
    esac
  fi
  local tmp
  tmp=$(registry_tmp)
  grep -v "^${name}|" "$PANE_REGISTRY" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$PANE_REGISTRY"
  echo "${name}|${role}|${pane}|${status}" >> "$PANE_REGISTRY"
}

reconcile_panes() {
  local panes tmp name id role pane
  panes=$(zellij_panes_json)
  tmp=$(registry_tmp)
  : > "$tmp"
  while IFS=$'\t' read -r name id; do
    [ -n "$name" ] || continue
    [ -n "$id" ] || continue
    role=$(role_from_name "$name")
    [ -n "$role" ] || continue
    pane="terminal_${id}"
    echo "${name}|${role}|${pane}|alive" >> "$tmp"
  done < <(jq -r '.[] | select(.exited | not) | [('"$pane_name_expr"'), (.id | tostring)] | @tsv' <<< "$panes" 2>/dev/null)
  mv "$tmp" "$PANE_REGISTRY"
}

rename_zellij_pane() {
  local pane="$1" name="$2"
  [ -n "$pane" ] || return 0
  [ -n "$name" ] || return 0
  zellij action rename-pane --pane-id "$pane" "$name" 2>/dev/null || true
}

adopt_existing_panes() {
  reconcile_panes
}

singleton_role() {
  case "$1" in
    dev-server|e2e|e2e-bug-hunt|ui-audit|watch-main|improve|feature-discovery|create-issue) return 0 ;;
    *) return 1 ;;
  esac
}

dedupe_singleton_role() {
  local role="$1" seen="" tmp
  tmp=$(registry_tmp)
  : > "$tmp"
  while IFS='|' read -r name r pane status; do
    [ -z "$name" ] && continue
    if [ "$r" = "$role" ] && [ "$status" = "alive" ]; then
      if [ -z "$seen" ]; then
        seen="$name"
        echo "${name}|${r}|${pane}|${status}" >> "$tmp"
      else
        zellij action close-pane --pane-id "$pane" 2>/dev/null || true
        write_pane_status_file "${STATUS_DIR}/${name}.json" "$name" "$role" \
          "⏹️ stopped" "deduplicated singleton role"
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

total_alive() {
  grep -c "|alive$" "$PANE_REGISTRY" 2>/dev/null || true
}

role_active() {
  local role="$1"
  [ "$(count_alive "$role")" -gt 0 ]
}

pane_name_active() {
  local target="$1"
  awk -F'|' -v target="$target" '$1 == target && $4 == "alive" { found = 1 } END { exit found ? 0 : 1 }' "$PANE_REGISTRY"
}

pane_matches_registry() {
  local expected_name="$1" expected_role="$2" pane="$3"
  local current_name current_role
  current_name=$(pane_current_name "$pane")
  [ -n "$current_name" ] || return 1
  current_role=$(role_from_name "$current_name")
  [ "$current_role" = "$expected_role" ] || return 1

  case "$expected_name" in
    review-pr-*|fix-review-pr-*|implement-issue-*|dev-server|e2e|e2e-hunt|ui-audit|watch-main|improve)
      [ "$current_name" = "$expected_name" ]
      ;;
    *)
      return 0
      ;;
  esac
}

STALL_THRESHOLD="${ORCH_STALL_THRESHOLD:-600}"
STALLED_PANES=""

kill_stalled_panes() {
  STALLED_PANES=""
  local now tmp
  now=$(date +%s)
  tmp=$(registry_tmp)
  : > "$tmp"
  while IFS='|' read -r name role pane status; do
    [ -z "$name" ] && continue
    [ "$status" != "alive" ] && { echo "${name}|${role}|${pane}|${status}" >> "$tmp"; continue; }
    local epoch=0 state=""
    if [ -f "${STATUS_DIR}/${name}.json" ]; then
      epoch=$(jq -r '.epoch // 0' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo 0)
      state=$(jq -r '.state // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
    fi
    local age=$(( now - epoch ))
    if [ "$epoch" -gt 0 ] && [ "$age" -ge "$STALL_THRESHOLD" ] && [[ "$state" == *running* ]]; then
      STALLED_PANES="${STALLED_PANES} ${name}(${age}s)"
      zellij action close-pane --pane-id "$pane" 2>/dev/null || true
      write_pane_status_file "${STATUS_DIR}/${name}.json" "$name" "$role" \
        "💀 stalled" "stalled for ${age}s — auto-killed" "" "" "" 0 0 "$now"
    else
      echo "${name}|${role}|${pane}|${status}" >> "$tmp"
    fi
  done < "$PANE_REGISTRY"
  mv "$tmp" "$PANE_REGISTRY"
}

update_pane_status() {
  reconcile_panes
  dedupe_singleton_role "dev-server"
  reconcile_panes
  check_dev_server_health
  kill_stalled_panes
  cleanup_zombie_status
}

cleanup_zombie_status() {
  local now
  now=$(date +%s)
  for f in "${STATUS_DIR}"/*.json; do
    [ -f "$f" ] || continue
    local name state epoch
    name=$(jq -r '.agent // ""' "$f" 2>/dev/null || echo "")
    state=$(jq -r '.state // ""' "$f" 2>/dev/null || echo "")
    epoch=$(jq -r '.epoch // 0' "$f" 2>/dev/null || echo 0)
    [ -n "$name" ] || continue
    # Only check running/waiting states
    case "$state" in
      *running*|*waiting*|*ready*) ;;
      *) continue ;;
    esac
    # If this agent is in the registry as alive, it's fine
    grep -q "^${name}|" "$PANE_REGISTRY" 2>/dev/null && continue
    # Not in registry = pane is gone. Mark as finished.
    local zombie_tmp
    zombie_tmp=$(safe_tmp "$f") || continue
    if jq --arg ts "$(date '+%H:%M:%S')" --argjson epoch "$now" \
      '. + {state: "⏹️ finished", detail: "pane exited (auto-cleanup)", ts: $ts, epoch: $epoch}' \
      "$f" > "$zombie_tmp" 2>/dev/null; then
      mv -f "$zombie_tmp" "$f" 2>/dev/null || rm -f "$zombie_tmp"
    else
      rm -f "$zombie_tmp"
    fi
  done
}

add_pane() {
  local name="$1" role="$2" context="${3:-}" reason="${4:-}"
  # Guard: reject empty name
  if [ -z "$name" ]; then
    record_decision "error" "add_pane called with empty name" "role=${role}"
    return 1
  fi
  reconcile_panes
  if singleton_role "$role"; then
    dedupe_singleton_role "$role"
    while IFS='|' read -r n r _pane s; do
      [ "$r" = "$role" ] && [ "$s" = "alive" ] && return
    done < "$PANE_REGISTRY"
  fi
  while IFS='|' read -r n r _pane s; do
    [ "$n" = "$name" ] && [ "$s" = "alive" ] && return
  done < "$PANE_REGISTRY"

  # Also check zellij directly for same-name pane (race condition guard)
  if zellij_panes_json | jq -e --arg name "$name" '.[] | select(.exited | not) | select(('"$pane_name_expr"') == $name)' >/dev/null 2>&1; then
    return
  fi

  local tmp
  tmp=$(registry_tmp)
  grep -v "^${name}|" "$PANE_REGISTRY" > "$tmp" 2>/dev/null || true
  mv "$tmp" "$PANE_REGISTRY"

  local status_pr=""
  if [[ "$name" =~ -pr-([0-9]+)$ ]]; then
    status_pr="#${BASH_REMATCH[1]}"
  fi
  write_pane_status_file "${STATUS_DIR}/${name}.json" "$name" "$role" \
    "🚀 starting" "$reason" "$status_pr"
  resolve_agents_tab_id
  local pane context_b64 reason_b64
  context_b64=$(agent_arg_b64 "$context")
  reason_b64=$(agent_arg_b64 "$reason")
  local tab_args=()
  if [ -n "$AGENTS_TAB_ID" ] && [ "$AGENTS_TAB_ID" != "null" ]; then
    tab_args=(--tab-id "$AGENTS_TAB_ID")
  fi
  pane=$(zellij action new-pane "${tab_args[@]}" --close-on-exit --name "$name" --cwd "$PROJECT_CWD" \
    -- bash -lc "AGENT_ID='${name}' AGENT_CONTEXT_B64='${context_b64}' AGENT_REASON_B64='${reason_b64}' AGENT_ONCE=true AGENT_INTERVAL=30 ./scripts/agent.sh '${role}'")
  if [ -z "$pane" ] || ! pane_exists "$pane"; then
    write_pane_status_file "${STATUS_DIR}/${name}.json" "$name" "$role" \
      "❌ failed" "failed to create zellij pane" "" "" "" 0 1
    return 1
  fi
  rename_zellij_pane "$pane" "$name"
  close_agent_placeholder_panes
  record_registry_entry "$name" "$role" "$pane" "alive"
  reconcile_panes
}

kill_role() {
  local role="$1"
  local tmp
  tmp=$(registry_tmp)
  : > "$tmp"
  while IFS='|' read -r name r pane status; do
    [ -z "$name" ] && continue
    if [ "$r" = "$role" ] && [ "$status" = "alive" ]; then
      zellij action close-pane --pane-id "$pane" 2>/dev/null || true
      write_pane_status_file "${STATUS_DIR}/${name}.json" "$name" "$role" \
        "⏹️ stopped" "no longer needed"
    else
      echo "${name}|${r}|${pane}|${status}" >> "$tmp"
    fi
  done < "$PANE_REGISTRY"
  mv "$tmp" "$PANE_REGISTRY"
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
