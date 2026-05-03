#!/usr/bin/env bash
# tmux launcher for the Kiro pipeline.
# Keeps the same visible tab model as tmux windows: Pipeline, Control, Kiro.
set -euo pipefail

SESSION="${KIRO_TMUX_SESSION:-kiro-pipeline}"
PROJECT_CWD="$(pwd)"

attach_or_switch() {
  if [[ -n "${TMUX:-}" ]]; then
    tmux switch-client -t "$SESSION"
  else
    tmux attach-session -t "$SESSION"
  fi
}

if tmux has-session -t "$SESSION" 2>/dev/null; then
  attach_or_switch
  exit 0
fi

tmux new-session -d -s "$SESSION" -n Pipeline -c "$PROJECT_CWD" \
  "KIRO_TMUX_SESSION='$SESSION' KIRO_TMUX_WINDOW='Pipeline' ./scripts/orchestrator.sh"

tmux new-window -t "${SESSION}:" -n Control -c "$PROJECT_CWD" \
  "KIRO_TMUX_SESSION='$SESSION' KIRO_TMUX_WINDOW='Pipeline' ./scripts/control-panel.sh"

tmux new-window -t "${SESSION}:" -n Kiro -c "$PROJECT_CWD" \
  "kiro-cli chat --trust-all-tools"

tmux select-window -t "${SESSION}:Pipeline"
attach_or_switch
