#!/usr/bin/env bash
# Usage: ./scripts/agent.sh <prompt-name>
# Runs a kiro-cli agent in a loop, feeding it the specified prompt.
# Agents that depend on issues/PRs will wait until work is available.

set -euo pipefail

export GIT_EDITOR=true
export EDITOR=true
export VISUAL=true
export GIT_SEQUENCE_EDITOR=true

# Force no-editor at git config level (survives subprocesses that reset env)
git config --global core.editor true
git config --global sequence.editor true
git config --global rebase.autosquash true

PROMPT_NAME="${1:?Usage: agent.sh <prompt-name>}"
PROMPT_FILE=".kiro/prompts/${PROMPT_NAME}.md"
INTERVAL="${AGENT_INTERVAL:-120}"
ONCE="${AGENT_ONCE:-false}"
MAX_ERRORS=5
STATUS_DIR=".agent-status"
LOG_DIR=".agent-logs"
AGENT_NAME="${AGENT_ID:-$PROMPT_NAME}"
AGENT_CONTEXT="${AGENT_CONTEXT:-}"
AGENT_REASON="${AGENT_REASON:-}"
STATUS_FILE="${STATUS_DIR}/${AGENT_NAME}.json"
LOG_FILE="${LOG_DIR}/${AGENT_NAME}.log"

mkdir -p "$STATUS_DIR" "$LOG_DIR"

decode_b64_arg() {
  local value="$1"
  [ -n "$value" ] || return 0
  printf '%s' "$value" | base64 --decode 2>/dev/null \
    || printf '%s' "$value" | base64 -d 2>/dev/null \
    || printf '%s' "$value" | base64 -D 2>/dev/null \
    || true
}

[ -n "${AGENT_CONTEXT_B64:-}" ] && AGENT_CONTEXT="$(decode_b64_arg "$AGENT_CONTEXT_B64")"
[ -n "${AGENT_REASON_B64:-}" ] && AGENT_REASON="$(decode_b64_arg "$AGENT_REASON_B64")"

# Keep zellij pane title stable even if the shell/program changes terminal title.
printf '\033]2;%s\007' "$AGENT_NAME" 2>/dev/null || true
if [ -n "${ZELLIJ_PANE_ID:-}" ]; then
  zellij action rename-pane --pane-id "$ZELLIJ_PANE_ID" "$AGENT_NAME" 2>/dev/null || true
fi

# Tee all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

# ── Status tracking ──
# These vars are updated by scan_agent_context() after each cycle
CURRENT_ISSUE=""
CURRENT_PR=""
CURRENT_BRANCH=""

update_status() {
  local state="$1" detail="${2:-}"
  jq -n \
    --arg agent "$AGENT_NAME" \
    --arg prompt "$PROMPT_NAME" \
    --arg state "$state" \
    --arg detail "$detail" \
    --arg issue "$CURRENT_ISSUE" \
    --arg pr "$CURRENT_PR" \
    --arg branch "$CURRENT_BRANCH" \
    --arg ts "$(date '+%H:%M:%S')" \
    --argjson cycle "$cycle" \
    --argjson errors "$error_count" \
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
      ts: $ts
    }' > "$STATUS_FILE"
}

# Scan git state and GitHub to detect what this agent is working on
scan_agent_context() {
  # Current branch
  CURRENT_BRANCH=$(git branch --show-current 2>/dev/null || echo "")

  # Extract issue number from branch name (e.g., feat/issue-42-xxx → #42)
  if [[ "$CURRENT_BRANCH" =~ issue-([0-9]+) ]]; then
    CURRENT_ISSUE="#${BASH_REMATCH[1]}"
  elif [[ "$CURRENT_BRANCH" =~ ^[a-z]+/([0-9]+)- ]]; then
    CURRENT_ISSUE="#${BASH_REMATCH[1]}"
  fi

  # Check for open PR from this branch
  if [ -n "$CURRENT_BRANCH" ] && [ "$CURRENT_BRANCH" != "main" ]; then
    local pr_num
    pr_num=$(gh pr list --head "$CURRENT_BRANCH" --json number --jq '.[0].number' 2>/dev/null || echo "")
    [ -n "$pr_num" ] && CURRENT_PR="#${pr_num}"
  fi
}

if [[ ! -f "$PROMPT_FILE" ]]; then
  echo "❌ Prompt not found: $PROMPT_FILE"
  exit 1
fi

error_count=0
cycle=0

# Wait condition per agent type
wait_for_work() {
  case "$PROMPT_NAME" in
    dev-server)
      return 0
      ;;
    implement|watch-issues)
      echo "⏳ Waiting for open issues..."
      while true; do
        update_status "⏳ waiting" "issues"
        count=$(gh issue list --state open --json number --jq 'length' 2>/dev/null || echo "0")
        [[ "$count" -gt 0 ]] && return 0
        sleep 30
      done
      ;;
    review|watch-review)
      echo "⏳ Waiting for open PRs..."
      while true; do
        update_status "⏳ waiting" "PRs"
        count=$(gh pr list --json number --jq 'length' 2>/dev/null || echo "0")
        [[ "$count" -gt 0 ]] && return 0
        sleep 30
      done
      ;;
    fix-review)
      echo "⏳ Waiting for PRs with review comments..."
      while true; do
        update_status "⏳ waiting" "review comments"
        count=$(gh pr list --json number --jq 'length' 2>/dev/null || echo "0")
        [[ "$count" -gt 0 ]] && return 0
        sleep 30
      done
      ;;
    watch-main|e2e-bug-hunt)
      echo "⏳ Waiting for first merge to main..."
      while true; do
        update_status "⏳ waiting" "merge"
        count=$(gh pr list --state merged --json number --jq 'length' --limit 1 2>/dev/null || echo "0")
        [[ "$count" -gt 0 ]] && return 0
        sleep 30
      done
      ;;
    improve)
      echo "⏳ Waiting for first merge to main..."
      while true; do
        update_status "⏳ waiting" "merge"
        count=$(gh pr list --state merged --json number --jq 'length' --limit 1 2>/dev/null || echo "0")
        [[ "$count" -gt 0 ]] && return 0
        sleep 60
      done
      ;;
    *)
      return 0
      ;;
  esac
}

echo "🚀 Agent [${PROMPT_NAME}] initialized"
echo "   Prompt: ${PROMPT_FILE}"
echo "   Interval: ${INTERVAL}s"
[ -n "$AGENT_REASON" ] && echo "   Reason: ${AGENT_REASON}"
echo ""

# Phase 1: Wait for work
update_status "⏳ waiting" "$AGENT_REASON"
wait_for_work
update_status "🟢 ready" "$AGENT_REASON"
echo "✅ Work detected. Starting agent loop."
echo ""

# Phase 2: Run loop
while true; do
  cycle=$((cycle + 1))
  echo "━━━ Cycle #${cycle} [$(date '+%H:%M:%S')] ━━━"

  # Reset context for new cycle
  CURRENT_ISSUE=""
  CURRENT_PR=""
  CURRENT_BRANCH=""
  if [ -n "$AGENT_REASON" ]; then
    update_status "🔄 running" "cycle #${cycle}: ${AGENT_REASON}"
  else
    update_status "🔄 running" "cycle #${cycle}"
  fi

  PROMPT_BODY="$(cat "$PROMPT_FILE")"
  if [ -n "$AGENT_CONTEXT" ]; then
    PROMPT_BODY="${PROMPT_BODY}

## Orchestrator assignment

${AGENT_CONTEXT}"
  fi

  if kiro-cli chat \
    --no-interactive \
    --trust-all-tools \
    --resume \
    "$PROMPT_BODY" 2>&1; then
    error_count=0
    # Scan what the agent did
    scan_agent_context
    update_status "✅ done" "cycle #${cycle}"
    echo "✅ Cycle #${cycle} complete"
  else
    error_count=$((error_count + 1))
    scan_agent_context
    update_status "⚠️ error" "cycle #${cycle} (${error_count}/${MAX_ERRORS})"
    echo "⚠️  Cycle #${cycle} failed (${error_count}/${MAX_ERRORS})"
    [[ $error_count -ge $MAX_ERRORS ]] && update_status "💀 dead" "too many errors" && echo "❌ Too many errors. Stopping." && exit 1
  fi

  # Once mode: exit after single cycle (for orchestrator)
  if [[ "$ONCE" == "true" ]]; then
    if [ -n "$AGENT_REASON" ]; then
      update_status "⏹️ finished" "cycle #${cycle}: ${AGENT_REASON}"
    else
      update_status "⏹️ finished" "cycle #${cycle}"
    fi
    echo "🏁 Once mode — exiting."
    exit 0
  fi

  update_status "😴 sleeping" "next in ${INTERVAL}s"
  echo "⏳ Next cycle in ${INTERVAL}s..."
  sleep "$INTERVAL"
done
