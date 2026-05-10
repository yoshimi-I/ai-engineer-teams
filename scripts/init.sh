#!/usr/bin/env bash
# One-shot scaffold: turn a fresh clone of the ai-engineer-teams template
# into a new GitHub repository for your own project.
#
# This script is destructive by design: it removes template-only files
# (LICENSE, docs/, upstream README/AGENTS) and re-initializes git history.
# To guard against accidental invocation on a developer's own project we:
#   1. Refuse to run unless this directory looks like a clone of the
#      canonical upstream template (origin URL match OR no origin + marker).
#   2. Require an explicit y/N confirmation before deleting anything.
#
# Usage:
#   ./scripts/init.sh                 # prompts for repo name
#   ./scripts/init.sh my-new-project  # uses positional repo name

set -euo pipefail

BOLD='\033[1m'
DIM='\033[2m'
GREEN='\033[32m'
RED='\033[31m'
YELLOW='\033[33m'
RESET='\033[0m'

info() { echo -e "${GREEN}  ✔ $1${RESET}"; }
warn() { echo -e "${YELLOW}  ⚠ $1${RESET}"; }
fail() { echo -e "${RED}  ✗ $1${RESET}"; exit 1; }

echo ""
echo -e "${BOLD}  🚀 ai-engineer-teams — scaffold new project${RESET}"
echo ""

# ── Guard: only run from an upstream clone ─────────────────────────────────
UPSTREAM_TEMPLATE_REGEX='(^|[:/])yoshimi-I/ai-engineer-teams(\.git)?/?$'
REMOTE_URL="$(git remote get-url origin 2>/dev/null || true)"

HAS_UPSTREAM_ORIGIN=false
if [[ -n "$REMOTE_URL" && "$REMOTE_URL" =~ $UPSTREAM_TEMPLATE_REGEX ]]; then
  HAS_UPSTREAM_ORIGIN=true
fi

HAS_TEMPLATE_MARKER=false
if [[ -f README.md ]] && grep -q "ai-engineer-teams" README.md 2>/dev/null; then
  HAS_TEMPLATE_MARKER=true
fi

if [[ "$HAS_UPSTREAM_ORIGIN" != "true" && "$HAS_TEMPLATE_MARKER" != "true" ]]; then
  echo -e "${RED}  ✗ This does not look like a fresh clone of the upstream template.${RESET}"
  echo ""
  echo "  origin: ${REMOTE_URL:-(none)}"
  echo "  README.md template marker: $HAS_TEMPLATE_MARKER"
  echo ""
  echo "  init.sh is destructive (it deletes LICENSE/docs and rm -rf .git)."
  echo "  Refusing to run on what appears to be an existing project."
  echo ""
  echo "  If you are sure this is intended, clone the template fresh first:"
  echo "    git clone https://github.com/yoshimi-I/ai-engineer-teams.git <dir>"
  echo "    cd <dir> && ./scripts/init.sh"
  exit 1
fi

# ── Repo name prompt ───────────────────────────────────────────────────────
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
  fail "リポジトリ名が空です"
fi

if gh repo view "$REPO" &>/dev/null; then
  fail "'$REPO' は既にGitHubに存在します"
fi

# ── Explicit confirmation before destructive ops ───────────────────────────
echo -e "${YELLOW}  以下のファイル・履歴を削除します (取り消し不可):${RESET}"
echo "    - LICENSE (テンプレート由来)"
echo "    - docs/ ディレクトリ全体 (テンプレート由来)"
echo "    - README.md / AGENTS.md (テンプレート由来のみ)"
echo "    - .git/ ディレクトリ全体 (履歴を初期化)"
echo ""
echo "  その後、新しい git 履歴で以下を作成します:"
echo "    - GitHub リポジトリ: $REPO (private)"
echo "    - 初期コミット: 'init: scaffold from ai-engineer-teams'"
echo ""
read -r -p "  本当に続行しますか？ (y/N) → " CONFIRM
if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
  echo "  中止しました。"
  exit 0
fi
echo ""

# ── Remove template files ──────────────────────────────────────────────────
rm -f LICENSE
rm -rf docs
for f in README.md AGENTS.md; do
  grep -q "ai-engineer-teams" "$f" 2>/dev/null && rm -f "$f"
done

# ── Initialize git & create repo ───────────────────────────────────────────
rm -rf .git
git init -q
git add .
git commit -q -m "init: scaffold from ai-engineer-teams"
gh repo create "$REPO" --private --source=. --push > /dev/null 2>&1

echo -e "${GREEN}  ✔ $REPO を作成しました${RESET}"
echo ""
echo -e "  ${DIM}次: just setup → just start${RESET}"
echo ""
