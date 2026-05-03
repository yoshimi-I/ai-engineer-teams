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
  local tmp="${PANE_REGISTRY}.tmp"; : > "$tmp"
  local now; now=$(date +%s)
  while IFS='|' read -r name role pid status; do
    [ -z "$name" ] && continue
    local mtime=0
    [ -f "${STATUS_DIR}/${name}.json" ] && mtime=$(stat -f%m "${STATUS_DIR}/${name}.json" 2>/dev/null || stat -c%Y "${STATUS_DIR}/${name}.json" 2>/dev/null || echo 0)
    if [ $((now - mtime)) -lt 300 ]; then
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
{"agent":"${name}","prompt":"${role}","state":"🚀 starting","detail":"","issue":"","pr":"","branch":"","cycle":0,"errors":0,"ts":"$(date '+%H:%M:%S')"}
JSON
  zellij run --name "$name" --cwd "$PROJECT_CWD" \
    -- bash -c "AGENT_ID='${name}' AGENT_INTERVAL=30 ./scripts/agent.sh '${role}'" &
  local zpid=$!
  sleep 0.5  # Give zellij time to create the pane
  echo "${name}|${role}|${zpid}|alive" >> "$PANE_REGISTRY"
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

  # Table header
  printf "  \033[2m┌──────────────────────┬──────────────┬────────┬────────────────────────────────────────────────────────┐\033[0m\n"
  printf "  \033[2m│\033[0m \033[1m%-20s\033[0m \033[2m│\033[0m \033[1m%-12s\033[0m \033[2m│\033[0m \033[1m%-6s\033[0m \033[2m│\033[0m \033[1m%-54s\033[0m \033[2m│\033[0m\n" "Name" "Role" "State" "Detail"
  printf "  \033[2m├──────────────────────┼──────────────┼────────┼────────────────────────────────────────────────────────┤\033[0m\n"

  while IFS='|' read -r name role pid status; do
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
    local in_issues=false in_prs=false
    echo -e "  \033[1m📋 Current Work\033[0m"
    while IFS= read -r line; do
      case "$line" in
        "ISSUES_IN_PROGRESS:") in_issues=true; in_prs=false; echo -e "  \033[33mIssues (着手中):\033[0m" ;;
        "OPEN_PRS:") in_issues=false; in_prs=true; echo -e "  \033[36mPull Requests:\033[0m" ;;
        *)
          [ -n "$line" ] && echo -e "  \033[2m${line}\033[0m"
          ;;
      esac
    done < "$summary_file"
    echo ""
  fi
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

  # Implement: scale based on unassigned issues
  # 1 agent per 2 unassigned issues, min 1 if any issues exist, max 4
  local desired=0
  if [ "${ISSUES:-0}" -gt 0 ]; then
    desired=$(( (ISSUES + 1) / 2 ))
    [ $desired -lt 1 ] && desired=1
    [ $desired -gt 4 ] && desired=4
  fi
  while [ "$cur_impl" -lt "$desired" ]; do
    IMPL_SEQ=$((IMPL_SEQ + 1))
    add_pane "implement-${IMPL_SEQ}" "implement"
    cur_impl=$((cur_impl + 1))
    sleep 1  # Stagger pane creation
  done

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

# Initial scale — immediately spawn agents based on current issues
scale
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
  update_pane_status
  render
done
