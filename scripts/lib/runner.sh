#!/usr/bin/env bash
# AI runner abstraction.
#
# The pipeline can be driven by Kiro CLI, Claude Code, or Codex CLI, selected via
# the AI_RUNNER environment variable (legacy KIRO_AI_RUNNER is also honoured
# for backward compatibility):
#
#   AI_RUNNER=kiro     (default) — uses `kiro-cli`
#   AI_RUNNER=claude             — uses `claude` (Claude Code CLI)
#   AI_RUNNER=codex              — uses `codex` (Codex CLI)
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
# every runner-specific difference in one place so the rest of the
# pipeline does not branch on the runner.

if [ "${__AI_RUNNER_SH_LOADED:-0}" = "1" ]; then
  return 0
fi
__AI_RUNNER_SH_LOADED=1

# Resolve the runner choice, preferring the new neutral name and falling back
# to the legacy KIRO_AI_RUNNER. Export both so children inherit either spelling.
AI_RUNNER="${AI_RUNNER:-${KIRO_AI_RUNNER:-kiro}}"
KIRO_AI_RUNNER="$AI_RUNNER"
export AI_RUNNER KIRO_AI_RUNNER

ai_runner_binary() {
  case "$AI_RUNNER" in
    kiro)   echo "kiro-cli" ;;
    claude) echo "claude"   ;;
    codex)  echo "codex"    ;;
    *)      echo "kiro-cli" ;;
  esac
}

ai_runner_available() {
  command -v "$(ai_runner_binary)" >/dev/null 2>&1
}

ai_run_oneshot() {
  local prompt="$1"
  case "$AI_RUNNER" in
    codex)
      codex exec \
        --ask-for-approval never \
        --sandbox danger-full-access \
        "$prompt"
      ;;
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
  case "$AI_RUNNER" in
    codex)
      if [ -n "$prompt" ]; then
        codex "$prompt"
      else
        codex
      fi
      ;;
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
