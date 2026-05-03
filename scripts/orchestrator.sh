#!/usr/bin/env bash
# Orchestrator   : event-driven, reacts to agent status changes in real-time
set -uo pipefail

export GIT_EDITOR=true
export EDITOR=true

PROJECT_CWD="$(pwd)"
STATUS_DIR=".agent-status"
CACHE_DIR="${STATUS_DIR}/.cache"
CACHE_TTL=25
PANE_REGISTRY="${STATUS_DIR}/.panes"
GH_REFRESH=60  # GitHub API refresh interval (seconds)

mkdir -p "$STATUS_DIR" "$CACHE_DIR"
: > "$PANE_REGISTRY"

# ── GitHub API (cached) ──

gh_cached() {
  local key="$1"; shift
  local cache_file="${CACHE_DIR}/${key}"
  if [ -f "$cache_file" ]; then
    local age=$(( $(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null || echo 0) ))
    if [ $age -lt $CACHE_TTL ]; then
      cat "$cache_file"; return
    fi
  fi
  local result; result=$("$@" 2>/dev/null || echo "")
  echo "$result" > "$cache_file"; echo "$result"
}

refresh_github_state() {
  ISSUES=$(gh_cached issues gh issue list --state open --json number,assignees \
    --jq "[.[] | select(.assignees | length == 0)] | length")
  CHANGES_REQ=$(gh_cached prs_changes gh pr list --json number,reviewDecision \
    --jq '[.[] | select(.reviewDecision == "CHANGES_REQUESTED")] | length')
  HAS_MERGES=false
  local c; c=$(gh_cached prs_merged gh pr list --state merged --limit 1 --json number --jq 'length')
  [ "${c:-0}" -gt 0 ] && HAS_MERGES=true
}

# ── Pane management ──

count_role() { grep "|${1}|" "$PANE_REGISTRY" 2>/dev/null | wc -l | tr -d ' '; }

add_pane() {
  local name="$1" role="$2"
  # Skip if already exists
  grep -q "^${name}|" "$PANE_REGISTRY" 2>/dev/null && return

  cat > "${STATUS_DIR}/${name}.json" <<JSON
{"agent":"${name}","prompt":"${role}","state":"🚀 starting","detail":"","cycle":0,"errors":0,"ts":"$(date '+%H:%M:%S')"}
JSON
  zellij run --name "$name" --cwd "$PROJECT_CWD" --close-on-exit \
    -- bash -c "AGENT_ID='${name}' AGENT_ONCE=true AGENT_INTERVAL=10 ./scripts/agent.sh '${role}'" &
  echo "${name}|${role}|$!" >> "$PANE_REGISTRY"
  log "➕ ${name} (${role})"
}

cleanup_dead() {
  local tmp="${PANE_REGISTRY}.tmp"; : > "$tmp"
  while IFS='|' read -r name role pid; do
    [ -z "$name" ] && continue
    if kill -0 "$pid" 2>/dev/null; then
      echo "${name}|${role}|${pid}" >> "$tmp"
    else
      log "♻️  ${name} 完了"
      rm -f "${STATUS_DIR}/${name}.json"
    fi
  done < "$PANE_REGISTRY"
  mv "$tmp" "$PANE_REGISTRY"
}

# ── Display ──

log() { echo -e "  \033[2m$(date '+%H:%M:%S')\033[0m $1"; }

render() {
  clear
  echo -e "\033[1m\033[36m"
  echo "  ╔══════════════════════════════════════════════════════════════╗"
  echo "  ║        🎭  O R C H E S T R A T O R        🎭              ║"
  echo "  ║              イベント駆動 · リアルタイム                    ║"
  echo "  ╚══════════════════════════════════════════════════════════════╝"
  echo -e "\033[0m"

  local total; total=$(wc -l < "$PANE_REGISTRY" | tr -d ' ')
  echo -e "  \033[2m$(date '+%H:%M:%S')\033[0m  \033[36m▶ ${total} panes\033[0m  📋 issue: \033[33m${ISSUES:-?}\033[0m  🔧 要修正: \033[31m${CHANGES_REQ:-?}\033[0m  🔀 merge: $(if ${HAS_MERGES:-false}; then echo -e '\033[32m✓\033[0m'; else echo -e '\033[2m-\033[0m'; fi)"
  echo ""

  # Pane table
  echo -e "  \033[2m┌──────────────────────┬──────────────┬──────────────────────────────┐\033[0m"
  printf "  \033[2m│\033[0m \033[1m%-20s\033[0m \033[2m│\033[0m \033[1m%-12s\033[0m \033[2m│\033[0m \033[1m%-28s\033[0m \033[2m│\033[0m\n" "Name" "Role" "Status"
  echo -e "  \033[2m├──────────────────────┼──────────────┼──────────────────────────────┤\033[0m"

  while IFS='|' read -r name role pid; do
    [ -z "$name" ] && continue
    local st="" dt=""
    if [ -f "${STATUS_DIR}/${name}.json" ]; then
      st=$(jq -r '.state // "?"' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "?")
      dt=$(jq -r '.detail // ""' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
    fi
    [ ${#dt} -gt 16 ] && dt="${dt:0:15}…"
    local c
    case "$role" in
      implement)    c="\033[33m" ;;
      fix-review)   c="\033[31m" ;;
      dev-server)   c="\033[32m" ;;
      watch-main)   c="\033[35m" ;;
      e2e-bug-hunt) c="\033[36m" ;;
      improve)      c="\033[34m" ;;
      *)            c="\033[2m" ;;
    esac
    printf "  \033[2m│\033[0m ${c}%-20s\033[0m \033[2m│\033[0m %-12s \033[2m│\033[0m %-28s \033[2m│\033[0m\n" "$name" "$role" "${st} ${dt}"
  done < "$PANE_REGISTRY"

  if [ "$(wc -l < "$PANE_REGISTRY" | tr -d ' ')" -eq 0 ]; then
    printf "  \033[2m│ %-20s │ %-12s │ %-28s │\033[0m\n" "(起動中...)" "" ""
  fi
  echo -e "  \033[2m└──────────────────────┴──────────────┴──────────────────────────────┘\033[0m"
  echo ""
}

# ── Scaling logic ──

scale() {
  cleanup_dead

  local cur_impl; cur_impl=$(count_role "implement")
  local cur_fix;  cur_fix=$(count_role "fix-review")
  local cur_dev;  cur_dev=$(count_role "dev-server")
  local cur_watch; cur_watch=$(count_role "watch-main")
  local cur_e2e;  cur_e2e=$(count_role "e2e-bug-hunt")
  local cur_imp;  cur_imp=$(count_role "improve")
  local total; total=$(wc -l < "$PANE_REGISTRY" | tr -d ' ')

  # Hard cap: never exceed 8 total panes
  if [ "$total" -ge 8 ]; then return; fi

  # Implement: 1 per 5 issues, min 1 if issues > 0, max 4
  # Only add if there are MORE unassigned issues than running impl agents
  local desired=0
  if [ "${ISSUES:-0}" -gt 0 ]; then
    desired=$(( (ISSUES + 4) / 5 ))
    [ $desired -gt 4 ] && desired=4
    [ $desired -lt 1 ] && desired=1
  fi
  # Only add ONE at a time to prevent explosion
  if [ "$cur_impl" -lt "$desired" ] && [ "$total" -lt 8 ]; then
    IMPL_SEQ=$((IMPL_SEQ + 1))
    add_pane "implement-${IMPL_SEQ}" "implement"
  fi

  # Fix-review: max 1
  if [ "${CHANGES_REQ:-0}" -gt 0 ] && [ "$cur_fix" -eq 0 ] && [ "$total" -lt 8 ]; then
    add_pane "fix-review" "fix-review"
  fi

  # Dev-server: only if project needs it and not already running
  if [ "$cur_impl" -gt 0 ] && [ "$cur_dev" -eq 0 ] && [ "$total" -lt 8 ]; then
    if [ -f "package.json" ] || [ -f "pyproject.toml" ] || [ -f "Cargo.toml" ]; then
      add_pane "dev-server" "dev-server"
    fi
  fi

  # Post-merge agents: one each, only after merge
  if ${HAS_MERGES:-false}; then
    [ "$cur_watch" -eq 0 ] && [ "$total" -lt 8 ] && add_pane "watch-main" "watch-main"
    [ "$cur_e2e" -eq 0 ]   && [ "$total" -lt 8 ] && add_pane "e2e-hunt" "e2e-bug-hunt"
    [ "$cur_imp" -eq 0 ]   && [ "$total" -lt 8 ] && add_pane "improve" "improve"
  fi
}

# ── Main ──

echo -e "\033[1m\033[36m  🎭 Orchestrator    起動\033[0m"
echo ""

IMPL_SEQ=0
ISSUES=0; CHANGES_REQ=0; HAS_MERGES=false
last_gh_refresh=0

# Initial GitHub state + first agent
refresh_github_state
IMPL_SEQ=1
add_pane "implement-1" "implement"
render

# Watch for status file changes + periodic GitHub refresh
while true; do
  # Wait for file change (2s timeout)
  if command -v fswatch >/dev/null 2>&1; then
    fswatch -1 --latency 2 "$STATUS_DIR" 2>/dev/null || sleep 3
  else
    sleep 3
  fi

  # Refresh GitHub state periodically
  now=$(date +%s)
  if [ $((now - last_gh_refresh)) -ge $GH_REFRESH ]; then
    refresh_github_state
    last_gh_refresh=$now
  fi

  scale
  render
done
