#!/usr/bin/env bash
# Orchestrator v2: starts minimal, adds/removes panes as needed
set -euo pipefail

export GIT_EDITOR=true
export EDITOR=true

POLL_INTERVAL="${ORCH_INTERVAL:-30}"
PROJECT_CWD="$(pwd)"
STATUS_DIR=".agent-status"
CACHE_DIR="${STATUS_DIR}/.cache"
CACHE_TTL=25
PANE_REGISTRY="${STATUS_DIR}/.panes"

mkdir -p "$STATUS_DIR" "$CACHE_DIR"
: > "$PANE_REGISTRY"

# ── Cached GitHub API ──

gh_cached() {
  local key="$1"; shift
  local cache_file="${CACHE_DIR}/${key}"
  if [ -f "$cache_file" ]; then
    local age=$(( $(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null || echo 0) ))
    if [ $age -lt $CACHE_TTL ]; then
      cat "$cache_file"
      return
    fi
  fi
  local result
  result=$("$@" 2>/dev/null || echo "")
  echo "$result" > "$cache_file"
  echo "$result"
}

count_unassigned_issues() {
  gh_cached issues gh issue list --state open --json number,assignees \
    --jq "[.[] | select(.assignees | length == 0)] | length"
}

count_prs_changes_requested() {
  gh_cached prs_changes gh pr list --json number,reviewDecision \
    --jq '[.[] | select(.reviewDecision == "CHANGES_REQUESTED")] | length'
}

has_merged_prs() {
  local c
  c=$(gh_cached prs_merged gh pr list --state merged --limit 1 --json number --jq 'length')
  [ "${c:-0}" -gt 0 ]
}

# ── Pane management ──

# Registry format: name|role|pid (one per line)

list_panes() {
  cat "$PANE_REGISTRY" 2>/dev/null
}

count_panes_by_role() {
  local role="$1"
  grep "|${role}|" "$PANE_REGISTRY" 2>/dev/null | wc -l | tr -d ' '
}

is_pane_alive() {
  local name="$1"
  local pid
  pid=$(grep "^${name}|" "$PANE_REGISTRY" 2>/dev/null | cut -d'|' -f3)
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

add_pane() {
  local name="$1" role="$2"

  # Write status
  cat > "${STATUS_DIR}/${name}.json" <<JSON
{"agent":"${name}","prompt":"${role}","state":"🔄 starting","detail":"","cycle":0,"errors":0,"ts":"$(date '+%H:%M:%S')"}
JSON

  # Launch
  zellij run \
    --name "$name" \
    --cwd "$PROJECT_CWD" \
    --close-on-exit \
    -- bash -c "AGENT_ID='${name}' AGENT_ONCE=true AGENT_INTERVAL=10 ./scripts/agent.sh '${role}'" &

  local pid=$!
  echo "${name}|${role}|${pid}" >> "$PANE_REGISTRY"
  echo "  ➕ ${name} (${role}) pid=${pid}"
}

remove_pane() {
  local name="$1"
  local pid
  pid=$(grep "^${name}|" "$PANE_REGISTRY" 2>/dev/null | cut -d'|' -f3)
  if [ -n "$pid" ]; then
    kill "$pid" 2>/dev/null || true
  fi
  # Remove from registry
  grep -v "^${name}|" "$PANE_REGISTRY" > "${PANE_REGISTRY}.tmp" 2>/dev/null || true
  mv "${PANE_REGISTRY}.tmp" "$PANE_REGISTRY"
  rm -f "${STATUS_DIR}/${name}.json"
  echo "  ➖ ${name}"
}

cleanup_dead_panes() {
  local tmp="${PANE_REGISTRY}.alive"
  : > "$tmp"
  while IFS='|' read -r name role pid; do
    [ -z "$name" ] && continue
    if kill -0 "$pid" 2>/dev/null; then
      echo "${name}|${role}|${pid}" >> "$tmp"
    else
      rm -f "${STATUS_DIR}/${name}.json"
    fi
  done < "$PANE_REGISTRY"
  mv "$tmp" "$PANE_REGISTRY"
}

# ── Main loop ──

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🎭 オーケストレーター v2"
echo "  📊 ${POLL_INTERVAL}秒ごとにポーリング"
echo "  🚀 最小構成で開始 → 必要に応じてpane追加"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Start with 1 implement agent
add_pane "implement-1" "implement"

cycle=0
impl_counter=1

while true; do
  cycle=$((cycle + 1))
  sleep "$POLL_INTERVAL"

  # Cleanup dead panes
  cleanup_dead_panes

  # Gather state
  issues=$(count_unassigned_issues)
  changes_req=$(count_prs_changes_requested)
  has_merges=false
  has_merged_prs && has_merges=true

  current_impl=$(count_panes_by_role "implement")
  current_fix=$(count_panes_by_role "fix-review")
  current_dev=$(count_panes_by_role "dev-server")
  current_watch=$(count_panes_by_role "watch-main")
  current_e2e=$(count_panes_by_role "e2e-bug-hunt")
  current_improve=$(count_panes_by_role "improve")

  echo "━━━ cycle #${cycle} [$(date '+%H:%M:%S')] ━━━"
  echo "  📋 未着手issue: ${issues}  🔧 要修正PR: ${changes_req}"
  echo "  🔨 impl: ${current_impl}  🔧 fix: ${current_fix}  🖥️ dev: ${current_dev}"
  echo "  👀 watch: ${current_watch}  🧪 e2e: ${current_e2e}  💡 improve: ${current_improve}"

  # ── Scale implement agents ──
  # 1 impl per 3 issues, min 1, max 8
  if [ "$issues" -gt 0 ]; then
    desired_impl=$(( (issues + 2) / 3 ))
    [ $desired_impl -gt 8 ] && desired_impl=8
    [ $desired_impl -lt 1 ] && desired_impl=1
  else
    desired_impl=0
  fi

  while [ "$current_impl" -lt "$desired_impl" ]; do
    impl_counter=$((impl_counter + 1))
    add_pane "implement-${impl_counter}" "implement"
    current_impl=$((current_impl + 1))
  done

  # ── Add fix-review if needed ──
  if [ "$changes_req" -gt 0 ] && [ "$current_fix" -eq 0 ]; then
    add_pane "fix-review-1" "fix-review"
  elif [ "$changes_req" -gt 2 ] && [ "$current_fix" -lt 2 ]; then
    add_pane "fix-review-2" "fix-review"
  fi

  # ── Add dev-server if impl agents are running and no dev-server ──
  if [ "$current_impl" -gt 0 ] && [ "$current_dev" -eq 0 ]; then
    # Check if project has a dev server config
    if [ -f "package.json" ] || [ -f "pyproject.toml" ] || [ -f "Cargo.toml" ]; then
      add_pane "dev-server" "dev-server"
    fi
  fi

  # ── Add watch-main + e2e after first merge ──
  if $has_merges; then
    if [ "$current_watch" -eq 0 ]; then
      add_pane "watch-main" "watch-main"
    fi
    if [ "$current_e2e" -eq 0 ]; then
      add_pane "e2e-hunt" "e2e-bug-hunt"
    fi
    if [ "$current_improve" -eq 0 ]; then
      add_pane "improve" "improve"
    fi
  fi

  # ── Show active panes ──
  echo "  📊 アクティブpane:"
  while IFS='|' read -r name role pid; do
    [ -z "$name" ] && continue
    echo "    ${name} (${role})"
  done < "$PANE_REGISTRY"
  echo ""
done
