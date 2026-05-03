#!/usr/bin/env bash
# Install prerequisites and clean up template files
# Usage: ./scripts/setup.sh

set -euo pipefail

info()  { echo "✅ $1"; }
warn()  { echo "⚠️  $1"; }
install_msg() { echo "📦 Installing $1..."; }

# ── Clean up template files (if cloned/degit'd) ──
for f in README.md docs/README.ja.md LICENSE docs; do
  if [[ -e "$f" ]]; then
    # Only remove if it's the template's file (check for kiro-engineer-teams marker)
    if grep -q "kiro-engineer-teams" "$f" 2>/dev/null; then
      rm -rf "$f"
      info "Removed template file: $f"
    fi
  fi
done
# Remove empty docs/ dir
rmdir docs 2>/dev/null || true

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

# ── tmux ──
if command -v tmux &>/dev/null; then
  info "tmux already installed"
else
  install_msg "tmux"
  case "$PKG" in
    brew) brew install tmux ;;
    apt)  sudo apt-get install -y tmux ;;
    dnf)  sudo dnf install -y tmux ;;
    *)    warn "Install tmux manually: https://github.com/tmux/tmux/wiki" ;;
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
