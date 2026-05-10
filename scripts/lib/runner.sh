#!/usr/bin/env bash
# AI runner abstraction.
#
# The pipeline can be driven by either Kiro CLI or Claude Code, selected via
# the KIRO_AI_RUNNER environment variable:
#
#   KIRO_AI_RUNNER=kiro     (default) — uses `kiro-cli`
#   KIRO_AI_RUNNER=claude            — uses `claude` (Claude Code CLI)
#
# Two entry points are exposed:
#
#   ai_run_oneshot <prompt>     — run the prompt non-interactively, exit when done.
#                                 Used by agent.sh in its loop and by the AI
#                                 planner inside lib/planner.sh.
#   ai_run_interactive <prompt> — open an interactive session seeded with the
#                                 given prompt. Used by operator.sh and the
#                                 INCEPTION launcher in start-pipeline.sh.
#
# Each runner has a different surface for these two modes; this file keeps
# every kiro-cli vs claude difference in one place so the rest of the
# pipeline does not branch on the runner.

if [ "${__KIRO_RUNNER_SH_LOADED:-0}" = "1" ]; then
  return 0
fi
__KIRO_RUNNER_SH_LOADED=1

KIRO_AI_RUNNER="${KIRO_AI_RUNNER:-kiro}"

ai_runner_binary() {
  case "$KIRO_AI_RUNNER" in
    kiro)   echo "kiro-cli" ;;
    claude) echo "claude"   ;;
    *)      echo "kiro-cli" ;;
  esac
}

ai_runner_available() {
  command -v "$(ai_runner_binary)" >/dev/null 2>&1
}

ai_run_oneshot() {
  local prompt="$1"
  case "$KIRO_AI_RUNNER" in
    claude)
      # `claude --print` is Claude Code's headless mode. We bypass permission
      # prompts because agents run unattended in zellij panes; the equivalent
      # Kiro option is `--trust-all-tools`. `--continue` resumes the most
      # recent session in this working directory, mirroring kiro `--resume`.
      claude \
        --print \
        --permission-mode bypassPermissions \
        --continue \
        "$prompt"
      ;;
    kiro|*)
      kiro-cli chat \
        --no-interactive \
        --trust-all-tools \
        --resume \
        "$prompt"
      ;;
  esac
}

ai_run_interactive() {
  local prompt="$1"
  case "$KIRO_AI_RUNNER" in
    claude)
      # In interactive mode we want the user to see the conversation. We do
      # NOT pass --permission-mode here so Claude Code uses the project's
      # .claude/settings.json (which already trusts the safe tool surface).
      if [ -n "$prompt" ]; then
        claude "$prompt"
      else
        claude
      fi
      ;;
    kiro|*)
      if [ -n "$prompt" ]; then
        kiro-cli chat --trust-all-tools "$prompt"
      else
        kiro-cli chat --trust-all-tools
      fi
      ;;
  esac
}
