#!/usr/bin/env bash
# Reset local pipeline runtime state, keeping INCEPTION / AI-DLC artifacts.
set -euo pipefail

echo "🔄 Restarting pipeline from the first post-INCEPTION cycle"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

if [[ ! -d ".kiro/prompts" ]]; then
  echo "❌ Run from project root (no .kiro/prompts/ found)"
  exit 1
fi

if [[ ! -d "aidlc-docs/inception" ]] || ! ls aidlc-docs/inception/*/*.md >/dev/null 2>&1; then
  echo "⚠️  INCEPTION artifacts were not found."
  echo "   Falling back to ./scripts/start-pipeline.sh so AI-DLC can run first."
  exec ./scripts/start-pipeline.sh
fi

echo "Keeping:"
echo "  - aidlc-docs/"
echo "  - issue/task.md"
echo "  - GitHub issues and PRs"
echo ""
echo "Clearing local runtime state:"
echo "  - .agent-status/"
echo "  - .agent-logs/"
echo ""

rm -rf .agent-status .agent-logs
mkdir -p .agent-status .agent-logs

exec ./scripts/start-pipeline.sh
