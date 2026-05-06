#!/usr/bin/env bash
set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
RED='\033[31m'
RESET='\033[0m'

echo ""
echo -e "${BOLD}  🚀 kiro-engineer-teams${RESET}"
echo ""

# Repo name
DEFAULT_NAME="$(basename "$PWD")"

if [[ -n "${1:-}" ]]; then
  REPO="$1"
else
  echo -e "  ${DIM}Enterでディレクトリ名を使用、または別名を入力${RESET}"
  echo ""
  read -r -p "  リポジトリ名 ($DEFAULT_NAME): " REPO
  REPO="${REPO:-$DEFAULT_NAME}"
  echo ""
fi

if [[ -z "$REPO" ]]; then
  echo -e "${RED}  ✗ リポジトリ名が空です${RESET}"
  exit 1
fi

if gh repo view "$REPO" &>/dev/null; then
  echo -e "${RED}  ✗ '$REPO' は既にGitHubに存在します${RESET}"
  exit 1
fi

# Remove template files
rm -f LICENSE
rm -rf docs
for f in README.md AGENTS.md; do
  grep -q "kiro-engineer-teams" "$f" 2>/dev/null && rm -f "$f"
done

# Initialize git & create repo
rm -rf .git
git init -q
git add .
git commit -q -m "init: scaffold from kiro-engineer-teams"
gh repo create "$REPO" --private --source=. --push > /dev/null 2>&1

echo -e "${GREEN}  ✔ $REPO を作成しました${RESET}"
echo ""
echo -e "  ${DIM}次: just setup → just start${RESET}"
echo ""
