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
STATUS_FILE="${STATUS_DIR}/${AGENT_ID:-$PROMPT_NAME}.json"
LOG_FILE="${LOG_DIR}/${AGENT_ID:-$PROMPT_NAME}.log"

mkdir -p "$STATUS_DIR" "$LOG_DIR"

# Tee all output to log file
exec > >(tee -a "$LOG_FILE") 2>&1

update_status() {
  local state="$1" detail="${2:-}"
  cat > "$STATUS_FILE" <<JSON
{"agent":"${AGENT_ID:-$PROMPT_NAME}","prompt":"$PROMPT_NAME","state":"$state","detail":"$detail","cycle":$cycle,"errors":$error_count,"ts":"$(date '+%H:%M:%S')"}
JSON
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
      # No wait — start immediately
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
echo ""

# Phase 1: Wait for work
update_status "⏳ waiting" ""
wait_for_work
update_status "🟢 ready" ""
echo "✅ Work detected. Starting agent loop."
echo ""

# Phase 2: Run loop
while true; do
  cycle=$((cycle + 1))
  echo "━━━ Cycle #${cycle} [$(date '+%H:%M:%S')] ━━━"
  update_status "🔄 running" "cycle #${cycle}"

  if kiro-cli chat \
    --no-interactive \
    --trust-all-tools \
    --resume \
    "$(cat "$PROMPT_FILE")" 2>&1; then
    error_count=0
    update_status "✅ done" "cycle #${cycle}"
    echo "✅ Cycle #${cycle} complete"
  else
    error_count=$((error_count + 1))
    update_status "⚠️ error" "cycle #${cycle} (${error_count}/${MAX_ERRORS})"
    echo "⚠️  Cycle #${cycle} failed (${error_count}/${MAX_ERRORS})"
    [[ $error_count -ge $MAX_ERRORS ]] && update_status "💀 dead" "too many errors" && echo "❌ Too many errors. Stopping." && exit 1
  fi

  # Once mode: exit after single cycle (for orchestrator)
  if [[ "$ONCE" == "true" ]]; then
    update_status "⏹️ finished" "cycle #${cycle}"
    echo "🏁 Once mode — exiting."
    exit 0
  fi

  update_status "😴 sleeping" "next in ${INTERVAL}s"
  echo "⏳ Next cycle in ${INTERVAL}s..."
  sleep "$INTERVAL"
done
