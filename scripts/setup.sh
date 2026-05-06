#!/usr/bin/env bash
# Install prerequisites for the kiro-engineer-teams pipeline.
#
# This script ONLY installs tools (kiro-cli, zellij, gh, gum, jq, shellcheck,
# bats-core, fswatch). It never removes user files. Template cleanup is
# owned by scripts/start-pipeline.sh (which detects the upstream template
# origin and asks for confirmation before scaffolding a new repo) and
# scripts/init.sh (explicit one-shot scaffold).
#
# Before this change, this script ran an unconditional rm on LICENSE,
# README.md, docs/README.ja.md, and docs/ whenever those files contained
# the string "kiro-engineer-teams". That made `just setup` destroy
# documentation and license files on a fresh clone — directly opposite
# to what the Quick Start in README.md promises ("clone → just setup").
#
# Usage: ./scripts/setup.sh

set -euo pipefail

info()  { echo "✅ $1"; }
warn()  { echo "⚠️  $1"; }
install_msg() { echo "📦 Installing $1..."; }
version_ge() {
  local version="$1" minimum="$2"
  awk -v version="$version" -v minimum="$minimum" '
    BEGIN {
      split(version, v, ".")
      split(minimum, m, ".")
      for (i = 1; i <= 3; i++) {
        vi = v[i] + 0
        mi = m[i] + 0
        if (vi > mi) exit 0
        if (vi < mi) exit 1
      }
      exit 0
    }'
}

# ── Detect package manager ──
if command -v brew &>/dev/null; then
  PKG="brew"
elif command -v apt-get &>/dev/null; then
  PKG="apt"
elif command -v dnf &>/dev/null; then
  PKG="dnf"
else
  PKG="unknown"
fi

# ── Kiro CLI ──
if command -v kiro-cli &>/dev/null; then
  info "kiro-cli already installed"
else
  warn "kiro-cli not found. Install from https://kiro.dev/downloads/"
fi

# ── zellij ──
if command -v zellij &>/dev/null; then
  ZELLIJ_VERSION=$(zellij --version | awk '{print $2}')
  if version_ge "$ZELLIJ_VERSION" "0.44.1"; then
    info "zellij already installed (${ZELLIJ_VERSION})"
  else
    warn "zellij ${ZELLIJ_VERSION} found; 0.44.1+ is required for dynamic pane orchestration"
    case "$PKG" in
      brew) brew upgrade zellij || brew install zellij ;;
      *)    warn "Upgrade zellij manually: https://zellij.dev/" ;;
    esac
  fi
else
  install_msg "zellij"
  case "$PKG" in
    brew) brew install zellij ;;
    apt)  sudo apt-get install -y zellij 2>/dev/null || cargo install --locked zellij ;;
    *)    cargo install --locked zellij 2>/dev/null || warn "Install zellij manually: https://zellij.dev/" ;;
  esac
fi

# ── GitHub CLI ──
if command -v gh &>/dev/null; then
  info "gh already installed"
else
  install_msg "gh"
  case "$PKG" in
    brew) brew install gh ;;
    apt)  sudo apt-get install -y gh 2>/dev/null || warn "Install gh manually: https://cli.github.com/" ;;
    dnf)  sudo dnf install -y gh 2>/dev/null || warn "Install gh manually: https://cli.github.com/" ;;
    *)    warn "Install gh manually: https://cli.github.com/" ;;
  esac
fi

# ── gh auth ──
if gh auth status &>/dev/null; then
  info "gh authenticated"
else
  warn "gh not authenticated. Running: gh auth login"
  gh auth login
fi

# ── just (optional) ──
if command -v just &>/dev/null; then
  info "just already installed"
else
  install_msg "just (optional)"
  case "$PKG" in
    brew) brew install just ;;
    *)    warn "Install just manually: https://just.systems/" ;;
  esac
fi

# ── gum (for TUI control panel) ──
if command -v gum &>/dev/null; then
  info "gum already installed"
else
  install_msg "gum"
  case "$PKG" in
    brew) brew install gum ;;
    apt)  sudo mkdir -p /etc/apt/keyrings && curl -fsSL https://repo.charm.sh/apt/gpg.key | sudo gpg --dearmor -o /etc/apt/keyrings/charm.gpg && echo "deb [signed-by=/etc/apt/keyrings/charm.gpg] https://repo.charm.sh/apt/ * *" | sudo tee /etc/apt/sources.list.d/charm.list && sudo apt-get update && sudo apt-get install -y gum ;;
    *)    warn "Install gum manually: https://github.com/charmbracelet/gum" ;;
  esac
fi

# ── jq ──
if command -v jq &>/dev/null; then
  info "jq already installed"
else
  install_msg "jq"
  case "$PKG" in
    brew) brew install jq ;;
    apt)  sudo apt-get install -y jq ;;
    dnf)  sudo dnf install -y jq ;;
    *)    warn "Install jq manually: https://jqlang.github.io/jq/" ;;
  esac
fi

# ── shellcheck (for pre-commit + CI parity) ──
if command -v shellcheck &>/dev/null; then
  info "shellcheck already installed"
else
  install_msg "shellcheck"
  case "$PKG" in
    brew) brew install shellcheck ;;
    apt)  sudo apt-get install -y shellcheck ;;
    dnf)  sudo dnf install -y ShellCheck ;;
    *)    warn "Install shellcheck manually: https://www.shellcheck.net/" ;;
  esac
fi

# ── bats-core (BATS unit tests for scripts/lib) ──
# Required locally so ./scripts/check.sh has CI parity — the previous
# skip-if-missing behaviour let regressions sneak past developer machines.
if command -v bats &>/dev/null; then
  info "bats already installed"
else
  install_msg "bats-core"
  case "$PKG" in
    brew) brew install bats-core ;;
    apt)  sudo apt-get install -y bats ;;
    dnf)  sudo dnf install -y bats ;;
    *)    warn "Install bats-core manually: https://github.com/bats-core/bats-core" ;;
  esac
fi

echo ""
echo "🎉 Setup complete!"
echo ""
echo "Next steps:"
echo "  just start    # INCEPTION → パイプライン起動"

# ── fswatch (for event-driven orchestrator) ──
if command -v fswatch &>/dev/null; then
  info "fswatch already installed"
else
  install_msg "fswatch"
  case "$PKG" in
    brew) brew install fswatch ;;
    apt)  sudo apt-get install -y fswatch 2>/dev/null || warn "Install fswatch manually" ;;
    *)    warn "Install fswatch manually (optional, falls back to polling)" ;;
  esac
fi
