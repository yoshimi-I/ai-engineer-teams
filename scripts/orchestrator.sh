#!/usr/bin/env bash
# Orchestrator: dynamically assigns roles to 10 zellij panes
# based on current issue/PR state.
set -euo pipefail

export GIT_EDITOR=true
export EDITOR=true

POLL_INTERVAL="${ORCH_INTERVAL:-30}"
PANE_COUNT=12
PROJECT_CWD="$(pwd)"
STATUS_DIR=".agent-status"
CACHE_DIR=".agent-status/.cache"
CACHE_TTL=25  # seconds — slightly less than poll interval
mkdir -p "$STATUS_DIR" "$CACHE_DIR"

# ── Cached GitHub API ──

gh_cached() {
  local key="$1"; shift
  local cache_file="${CACHE_DIR}/${key}"
  # Return cache if fresh
  if [[ -f "$cache_file" ]]; then
    local age=$(( $(date +%s) - $(stat -f%m "$cache_file" 2>/dev/null || stat -c%Y "$cache_file" 2>/dev/null || echo 0) ))
    if [[ $age -lt $CACHE_TTL ]]; then
      cat "$cache_file"
      return
    fi
  fi
  # Fetch and cache
  local result
  result=$("$@" 2>/dev/null || echo "")
  echo "$result" > "$cache_file"
  echo "$result"
}

# ── Helpers ──

count_issues() {
  gh_cached issues gh issue list --state open --json number,assignees \
    --jq "[.[] | select(.assignees | length == 0)] | length"
}

count_prs_needing_review() {
  gh_cached prs_review gh pr list --json number,reviewDecision,reviews \
    --jq '[.[] | select(.reviewDecision == "" or .reviewDecision == "REVIEW_REQUIRED")] | length'
}

count_prs_changes_requested() {
  gh_cached prs_changes gh pr list --json number,reviewDecision \
    --jq '[.[] | select(.reviewDecision == "CHANGES_REQUESTED")] | length'
}

count_prs_approved() {
  gh_cached prs_approved gh pr list --json number,reviewDecision \
    --jq '[.[] | select(.reviewDecision == "APPROVED")] | length'
}

has_merged_prs() {
  local c
  c=$(gh_cached prs_merged gh pr list --state merged --limit 1 --json number --jq 'length')
  [[ "${c:-0}" -gt 0 ]]
}

# ── Role allocation ──
# Returns a newline-separated list of 10 roles
allocate_roles() {
  local issues="$1" need_review="$2" changes_req="$3" approved="$4" has_merges="$5"
  local roles=()

  # Slot 0: always dev-server
  roles+=(dev-server)

  # Remaining 11 slots to fill (12 - dev-server)
  local remaining=11
  local impl=0 fix=0 watch=0 e2e=0 improve=0

  # 1) Fix-review: 1 per 2 CHANGES_REQUESTED PRs (min 0, max 2)
  if [[ "$changes_req" -gt 0 ]]; then
    fix=$(( (changes_req + 1) / 2 ))
    [[ $fix -gt 2 ]] && fix=2
  fi

  # Review is handled by CI (kiro-cli-review-action) — no local review agents needed
  # Merge is handled by auto-merge.yml workflow

  # 3) Watch-main + E2E: 1 each if merges exist
  if $has_merges; then
    watch=1
    e2e=1
  fi

  # 4) Improve: 1 if merges exist and we have spare slots
  if $has_merges; then
    improve=1
  fi

  # 5) Impl: fill the rest (at least 1 if issues > 0)
  local used=$((fix + watch + e2e + improve))
  impl=$((remaining - used))
  [[ $impl -lt 0 ]] && impl=0

  # If no issues, keep slots idle
  if [[ "$issues" -eq 0 && "$impl" -gt 0 ]]; then
    impl=0
  fi

  # If nothing to do at all, keep slots idle
  local total=$((impl + fix + watch + e2e + improve))
  local idle=$((remaining - total))

  # Build role list
  for ((i=0; i<impl; i++));    do roles+=(implement); done
  for ((i=0; i<fix; i++));     do roles+=(fix-review); done
  [[ $watch -gt 0 ]]   && roles+=(watch-main)
  [[ $e2e -gt 0 ]]     && roles+=(e2e-bug-hunt)
  [[ $improve -gt 0 ]] && roles+=(improve)
  for ((i=0; i<idle; i++));    do roles+=(idle); done

  printf '%s\n' "${roles[@]}"
}

# ── Pane management ──

declare -A PANE_ROLE   # pane_index -> current role
declare -A PANE_PID    # pane_index -> background PID

for ((i=0; i<PANE_COUNT; i++)); do
  PANE_ROLE[$i]=""
  PANE_PID[$i]=""
done

dispatch_pane() {
  local idx="$1" role="$2"
  local agent_id

  # Name mapping
  case "$role" in
    dev-server)   agent_id="Dev-Server" ;;
    implement)    agent_id="Impl-${idx}" ;;
    review)       agent_id="Review-${idx}" ;;
    fix-review)   agent_id="Fix-Review-${idx}" ;;
    watch-main)   agent_id="Watch-Main" ;;
    e2e-bug-hunt) agent_id="E2E-Hunt" ;;
    improve)      agent_id="Improve" ;;
    idle)         agent_id="Idle-${idx}" ;;
  esac

  if [[ "$role" == "idle" ]]; then
    cat > "${STATUS_DIR}/${agent_id}.json" <<JSON
{"agent":"${agent_id}","prompt":"idle","state":"💤 idle","detail":"waiting for work","cycle":0,"errors":0,"ts":"$(date '+%H:%M:%S')"}
JSON
    PANE_ROLE[$idx]="$role"
    return
  fi

  # Launch via zellij run into the pane
  zellij run \
    --name "$agent_id" \
    --cwd "$PROJECT_CWD" \
    --close-on-exit \
    -- bash -c "AGENT_ID=${agent_id} AGENT_ONCE=true AGENT_INTERVAL=10 ./scripts/agent.sh ${role}" &

  PANE_PID[$idx]=$!
  PANE_ROLE[$idx]="$role"
}

# ── Main loop ──

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  🎭 Orchestrator started"
echo "  📊 Polling every ${POLL_INTERVAL}s"
echo "  🖥️  Managing ${PANE_COUNT} panes"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

cycle=0
while true; do
  cycle=$((cycle + 1))

  # Gather state
  issues=$(count_issues)
  need_review=$(count_prs_needing_review)
  changes_req=$(count_prs_changes_requested)
  approved=$(count_prs_approved)
  has_merges=false
  has_merged_prs && has_merges=true

  echo "━━━ Orchestrator cycle #${cycle} [$(date '+%H:%M:%S')] ━━━"
  echo "  📋 Unassigned issues: ${issues}"
  echo "  🔍 PRs needing review: ${need_review}"
  echo "  🔧 PRs changes requested: ${changes_req}"
  echo "  ✅ PRs approved (merge): ${approved}"
  echo ""

  # Allocate roles
  mapfile -t new_roles < <(allocate_roles "$issues" "$need_review" "$changes_req" "$approved" "$has_merges")

  # Show allocation
  echo "  🎭 Allocation:"
  for ((i=0; i<PANE_COUNT; i++)); do
    role="${new_roles[$i]:-idle}"
    prev="${PANE_ROLE[$i]:-}"
    changed=""
    [[ "$role" != "$prev" ]] && changed=" ← was ${prev:-none}"
    echo "    Pane ${i}: ${role}${changed}"
  done
  echo ""

  # Check which panes are free (finished or idle)
  for ((i=0; i<PANE_COUNT; i++)); do
    role="${new_roles[$i]:-idle}"
    prev="${PANE_ROLE[$i]:-}"
    pid="${PANE_PID[$i]:-}"

    # If pane has a running process, skip
    if [[ -n "$pid" ]] && kill -0 "$pid" 2>/dev/null; then
      continue
    fi

    # Pane is free — dispatch new role
    dispatch_pane "$i" "$role"
  done

  echo "  ⏳ Next check in ${POLL_INTERVAL}s..."
  echo ""
  sleep "$POLL_INTERVAL"
done
