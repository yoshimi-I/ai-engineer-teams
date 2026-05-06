#!/usr/bin/env bash
# Install kiro-engineer-teams into an existing project.
# Usage: curl -fsSL <raw-url>/scripts/install.sh | bash
#    or: bash <(curl -fsSL <raw-url>/scripts/install.sh)

set -euo pipefail

REPO="yoshimi-I/kiro-engineer-teams"
BRANCH="main"
BOLD='\033[1m' DIM='\033[2m' GREEN='\033[32m' RED='\033[31m' YELLOW='\033[33m' RESET='\033[0m'

info()  { echo -e "${GREEN}  ✔ $1${RESET}"; }
warn()  { echo -e "${YELLOW}  ⚠ $1${RESET}"; }
fail()  { echo -e "${RED}  ✗ $1${RESET}"; exit 1; }

echo ""
echo -e "${BOLD}  📦 Install kiro-engineer-teams${RESET}"
echo -e "${DIM}  Add the Kiro Engineer Teams pipeline to your existing project${RESET}"
echo ""

# ── Preflight ──
[[ ! -d ".git" ]] && fail "Not a git repository. Run from your project root."

# ── Clone to temp dir ──
WORK_DIR=$(mktemp -d)
trap 'rm -rf "$WORK_DIR"' EXIT
git clone --depth 1 --branch "$BRANCH" "https://github.com/${REPO}.git" "$WORK_DIR" 2>/dev/null

# ── Copy helpers ──
copy_dir() {
  local src="$WORK_DIR/$1"
  [[ ! -d "$src" ]] && return
  if [[ -d "$1" ]]; then
    warn "$1/ already exists — merging (won't overwrite existing files)"
    rsync -a --ignore-existing "$src/" "$1/"
  else
    cp -r "$src" "$1"
    info "$1/"
  fi
}

copy_file() {
  local src="$WORK_DIR/$1"
  [[ ! -f "$src" ]] && return
  if [[ -f "$1" ]]; then
    warn "$1 already exists — skipped"
  else
    mkdir -p "$(dirname "$1")"
    cp "$src" "$1"
    info "$1"
  fi
}

echo -e "${BOLD}  Copying files...${RESET}"
echo ""

copy_dir ".kiro"
copy_dir "scripts"
copy_file ".github/workflows/kiro-review.yml"
copy_file ".github/workflows/promote-main.yml"
copy_file ".github/PULL_REQUEST_TEMPLATE.md"
copy_file ".github/ISSUE_TEMPLATE/bug_report.md"
copy_file ".github/ISSUE_TEMPLATE/feature_request.md"

# ── Merge justfile recipes ──
RECIPES=("setup" "preflight" "start" "restart" "pipeline" "ja" "en")
RECIPE_BLOCKS=$(cat <<'JUST'

# ── kiro-engineer-teams ──

# Install prerequisites
setup:
    ./scripts/setup.sh

# Continue pipeline from existing INCEPTION artifacts when present
start:
    ./scripts/start-pipeline.sh

# Diagnose local/GitHub prerequisites before starting the pipeline
preflight:
    ./scripts/preflight.sh

# Restart pipeline from the first post-INCEPTION cycle
restart:
    ./scripts/restart-pipeline.sh

# Launch pipeline only (skip INCEPTION)
pipeline:
    @LAYOUT_TMP=$(mktemp /tmp/pipeline-XXXXXX.kdl) && \
    sed "s|__PROJECT_CWD__|$(pwd)|g" scripts/pipeline.kdl > "$$LAYOUT_TMP" && \
    zellij --layout "$$LAYOUT_TMP"; \
    rm -f "$$LAYOUT_TMP"

# Switch to Japanese
ja:
    @scripts/sed-i.sh 's/Always respond to the user in English\./Always respond to the user in Japanese./' .kiro/steering/development-rules.md
    @scripts/sed-i.sh 's/Always respond in English\./Always respond in Japanese./' AGENTS.md
    @echo "✅ Switched to Japanese"

# Switch to English
en:
    @scripts/sed-i.sh 's/Always respond to the user in Japanese\./Always respond to the user in English./' .kiro/steering/development-rules.md
    @scripts/sed-i.sh 's/Always respond in Japanese\./Always respond in English./' AGENTS.md
    @echo "✅ Switched to English"
JUST
)

if [[ -f "justfile" ]]; then
  missing=false
  for r in "${RECIPES[@]}"; do
    grep -q "^${r}:" "justfile" || { missing=true; break; }
  done
  if $missing; then
    echo "$RECIPE_BLOCKS" >> "justfile"
    info "justfile — appended pipeline recipes"
  else
    info "justfile — all recipes already present"
  fi
else
  cp "$WORK_DIR/justfile" "justfile"
  info "justfile"
fi

# ── Merge AGENTS.md ──
AGENTS_MARKER="## After INCEPTION"
if [[ -f "AGENTS.md" ]]; then
  if ! grep -q "$AGENTS_MARKER" "AGENTS.md"; then
    cat "$WORK_DIR/AGENTS.md" >> "AGENTS.md"
    info "AGENTS.md — appended pipeline config"
  else
    info "AGENTS.md — already configured"
  fi
else
  cp "$WORK_DIR/AGENTS.md" "AGENTS.md"
  info "AGENTS.md"
fi

copy_file "skills-lock.json"

# Make scripts executable
chmod +x scripts/*.sh 2>/dev/null || true

echo ""
echo -e "${GREEN}  ✔ Installation complete!${RESET}"
echo ""
echo -e "  Next steps:"
echo -e "    ${DIM}1.${RESET} just setup  ${DIM}# install prerequisites${RESET}"
echo -e "    ${DIM}2.${RESET} just start  ${DIM}# start INCEPTION + pipeline${RESET}"
echo -e "    ${DIM}3.${RESET} protect main ${DIM}# keep main green; integrate feature PRs into develop${RESET}"
echo ""
