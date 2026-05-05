#!/usr/bin/env bash

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
      dev-server|e2e|watch-main|improve) name="$role" ;;
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
    dev-server|e2e|e2e-bug-hunt|watch-main|improve|feature-discovery|create-issue) return 0 ;;
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
    review-pr-*|fix-review-pr-*|implement-issue-*|dev-server|e2e|e2e-hunt|watch-main|improve)
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
      jq -n --arg agent "$name" --arg prompt "$role" \
        --arg detail "stalled for ${age}s — auto-killed" \
        --arg ts "$(date '+%H:%M:%S')" --argjson epoch "$now" \
        '{agent:$agent,prompt:$prompt,state:"💀 stalled",detail:$detail,issue:"",pr:"",branch:"",cycle:0,errors:0,ts:$ts,epoch:$epoch}' \
        > "${STATUS_DIR}/${name}.json"
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
    name=$(jq -r '.agent // ""' "$f" 2>/dev/null || continue)
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
    jq --arg ts "$(date '+%H:%M:%S')" --argjson epoch "$now" \
      '. + {state: "⏹️ finished", detail: "pane exited (auto-cleanup)", ts: $ts, epoch: $epoch}' \
      "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
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
  jq -n \
    --arg agent "$name" \
    --arg prompt "$role" \
    --arg detail "$reason" \
    --arg pr "$status_pr" \
    --arg ts "$(date '+%H:%M:%S')" \
    '{
      agent: $agent,
      prompt: $prompt,
      state: "🚀 starting",
      detail: $detail,
      issue: "",
      pr: $pr,
      branch: "",
      cycle: 0,
      errors: 0,
      ts: $ts
    }' > "${STATUS_DIR}/${name}.json"
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
    jq -n \
      --arg agent "$name" \
      --arg prompt "$role" \
      --arg detail "failed to create zellij pane" \
      --arg ts "$(date '+%H:%M:%S')" \
      '{
        agent: $agent,
        prompt: $prompt,
        state: "❌ failed",
        detail: $detail,
        issue: "",
        pr: "",
        branch: "",
        cycle: 0,
        errors: 1,
        ts: $ts
      }' > "${STATUS_DIR}/${name}.json"
    return 1
  fi
  rename_zellij_pane "$pane" "$name"
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
      cat > "${STATUS_DIR}/${name}.json" <<JSON
{"agent":"${name}","prompt":"${role}","state":"⏹️ stopped","detail":"no longer needed","issue":"","pr":"","branch":"","cycle":0,"errors":0,"ts":"$(date '+%H:%M:%S')"}
JSON
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
