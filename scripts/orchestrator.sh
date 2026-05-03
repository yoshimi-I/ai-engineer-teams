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

mkdir -p "$STATUS_DIR" "$CACHE_DIR"
: > "$PANE_REGISTRY"

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
  ISSUES=$(gh_cached issues gh issue list --state open --json number,assignees \
    --jq "[.[] | select(.assignees | length == 0)] | length")
  CHANGES_REQ=$(gh_cached prs_changes gh pr list --json number,reviewDecision \
    --jq '[.[] | select(.reviewDecision == "CHANGES_REQUESTED")] | length')
  HAS_MERGES=false
  local c; c=$(gh_cached prs_merged gh pr list --state merged --limit 1 --json number --jq 'length')
  [ "${c:-0}" -gt 0 ] && HAS_MERGES=true
}

# ── Pane management ──

count_alive() {
  local role="$1" count=0
  while IFS='|' read -r name r pid status; do
    [ -z "$name" ] && continue
    [ "$r" = "$role" ] && [ "$status" = "alive" ] && count=$((count + 1))
  done < "$PANE_REGISTRY"
  echo $count
}

update_pane_status() {
  # Get live pane names from zellij
  local live_panes
  live_panes=$(zellij action dump-layout 2>/dev/null | grep 'name="' | grep -v 'tab ' | sed 's/.*name="\([^"]*\)".*/\1/' || echo "")

  local tmp="${PANE_REGISTRY}.tmp"; : > "$tmp"
  while IFS='|' read -r name role pid status; do
    [ -z "$name" ] && continue
    if echo "$live_panes" | grep -qx "$name"; then
      echo "${name}|${role}|${pid}|alive" >> "$tmp"
    else
      echo "${name}|${role}|${pid}|stopped" >> "$tmp"
    fi
  done < "$PANE_REGISTRY"
  mv "$tmp" "$PANE_REGISTRY"
}

add_pane() {
  local name="$1" role="$2"
  # Skip if already exists and alive
  while IFS='|' read -r n r p s; do
    [ "$n" = "$name" ] && [ "$s" = "alive" ] && return
  done < "$PANE_REGISTRY"

  # Remove old stopped entry with same name
  grep -v "^${name}|" "$PANE_REGISTRY" > "${PANE_REGISTRY}.tmp" 2>/dev/null || true
  mv "${PANE_REGISTRY}.tmp" "$PANE_REGISTRY"

  cat > "${STATUS_DIR}/${name}.json" <<JSON
{"agent":"${name}","prompt":"${role}","state":"🚀 starting","detail":"","cycle":0,"errors":0,"ts":"$(date '+%H:%M:%S')"}
JSON
  zellij run --name "$name" --cwd "$PROJECT_CWD" \
    -- bash -c "AGENT_ID='${name}' AGENT_INTERVAL=30 ./scripts/agent.sh '${role}'" &
  echo "${name}|${role}|$!|alive" >> "$PANE_REGISTRY"
}

total_alive() {
  grep "|alive$" "$PANE_REGISTRY" 2>/dev/null | wc -l | tr -d ' '
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
  echo -e "  \033[2m$(date '+%H:%M:%S')\033[0m  \033[32m▶ ${alive} 稼働\033[0m / ${total} 合計  📋 issue: \033[33m${ISSUES:-?}\033[0m  🔧 要修正: \033[31m${CHANGES_REQ:-?}\033[0m  🔀 merge: $(if ${HAS_MERGES:-false}; then echo -e '\033[32m✓\033[0m'; else echo -e '\033[2m-\033[0m'; fi)"
  echo ""

  echo -e "  \033[2m┌──────────────────────┬──────────────┬────────┬──────────────────────────────┐\033[0m"
  printf "  \033[2m│\033[0m \033[1m%-20s\033[0m \033[2m│\033[0m \033[1m%-12s\033[0m \033[2m│\033[0m \033[1m%-6s\033[0m \033[2m│\033[0m \033[1m%-28s\033[0m \033[2m│\033[0m\n" "Name" "Role" "State" "Detail"
  echo -e "  \033[2m├──────────────────────┼──────────────┼────────┼──────────────────────────────┤\033[0m"

  while IFS='|' read -r name role pid status; do
    [ -z "$name" ] && continue

    local detail=""
    if [ -f "${STATUS_DIR}/${name}.json" ]; then
      detail=$(jq -r '"\(.state) \(.detail // "")"' "${STATUS_DIR}/${name}.json" 2>/dev/null || echo "")
    fi
    [ ${#detail} -gt 26 ] && detail="${detail:0:25}…"

    local color state_icon
    if [ "$status" = "alive" ]; then
      state_icon="\033[32m● 稼働\033[0m"
    else
      state_icon="\033[31m○ 停止\033[0m"
    fi

    case "$role" in
      implement)    color="\033[33m" ;;
      fix-review)   color="\033[31m" ;;
      dev-server)   color="\033[32m" ;;
      watch-main)   color="\033[35m" ;;
      e2e-bug-hunt) color="\033[36m" ;;
      improve)      color="\033[34m" ;;
      *)            color="\033[2m" ;;
    esac

    printf "  \033[2m│\033[0m ${color}%-20s\033[0m \033[2m│\033[0m %-12s \033[2m│\033[0m ${state_icon} \033[2m│\033[0m %-28s \033[2m│\033[0m\n" "$name" "$role" "" "$detail"
  done < "$PANE_REGISTRY"

  if [ "$(wc -l < "$PANE_REGISTRY" | tr -d ' ')" -eq 0 ]; then
    printf "  \033[2m│ %-20s │ %-12s │ %-6s │ %-28s │\033[0m\n" "(起動中...)" "" "" ""
  fi
  echo -e "  \033[2m└──────────────────────┴──────────────┴────────┴──────────────────────────────┘\033[0m"
  echo ""
}

# ── Scaling ──

scale() {
  update_pane_status
  local alive; alive=$(total_alive)

  # Hard cap
  [ "$alive" -ge 8 ] && return

  local cur_impl; cur_impl=$(count_alive "implement")
  local cur_fix;  cur_fix=$(count_alive "fix-review")
  local cur_dev;  cur_dev=$(count_alive "dev-server")
  local cur_watch; cur_watch=$(count_alive "watch-main")
  local cur_e2e;  cur_e2e=$(count_alive "e2e-bug-hunt")
  local cur_imp;  cur_imp=$(count_alive "improve")

  # Implement: 1 per 5 issues, max 4, add one at a time
  local desired=0
  [ "${ISSUES:-0}" -gt 0 ] && desired=$(( (ISSUES + 4) / 5 ))
  [ $desired -gt 4 ] && desired=4
  [ $desired -lt 1 ] && [ "${ISSUES:-0}" -gt 0 ] && desired=1
  if [ "$cur_impl" -lt "$desired" ]; then
    IMPL_SEQ=$((IMPL_SEQ + 1))
    add_pane "implement-${IMPL_SEQ}" "implement"
  fi

  # Fix-review
  [ "${CHANGES_REQ:-0}" -gt 0 ] && [ "$cur_fix" -eq 0 ] && add_pane "fix-review" "fix-review"

  # Dev-server
  if [ "$cur_impl" -gt 0 ] && [ "$cur_dev" -eq 0 ]; then
    [ -f "package.json" ] || [ -f "pyproject.toml" ] || [ -f "Cargo.toml" ] && add_pane "dev-server" "dev-server"
  fi

  # Post-merge
  if ${HAS_MERGES:-false}; then
    [ "$cur_watch" -eq 0 ] && add_pane "watch-main" "watch-main"
    [ "$cur_e2e" -eq 0 ]   && add_pane "e2e-hunt" "e2e-bug-hunt"
    [ "$cur_imp" -eq 0 ]   && add_pane "improve" "improve"
  fi
}

# ── Main ──

IMPL_SEQ=0; ISSUES=0; CHANGES_REQ=0; HAS_MERGES=false; last_gh=0

refresh_github
IMPL_SEQ=1; add_pane "implement-1" "implement"
render

while true; do
  if command -v fswatch >/dev/null 2>&1; then
    fswatch -1 --latency 3 "$STATUS_DIR" 2>/dev/null || sleep 5
  else
    sleep 5
  fi

  now=$(date +%s)
  [ $((now - last_gh)) -ge $GH_REFRESH ] && refresh_github && last_gh=$now

  scale
  render
done
