#!/usr/bin/env bash
# Update kiro-engineer-teams to the latest version
# Usage: ./scripts/update.sh
#   or:  bash <(curl -fsSL https://raw.githubusercontent.com/yoshimi-I/kiro-engineer-teams/main/scripts/update.sh)
set -euo pipefail

REPO="yoshimi-I/kiro-engineer-teams"
BRANCH="main"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

echo "🔄 Updating kiro-engineer-teams..."
echo ""

# Download latest
curl -fsSL "https://github.com/${REPO}/archive/refs/heads/${BRANCH}.tar.gz" | tar xz -C "$TMP"
SRC="${TMP}/kiro-engineer-teams-${BRANCH}"

# Files to update (overwrite)
TARGETS=(
  "scripts/agent.sh"
  "scripts/orchestrator.sh"
  "scripts/dashboard.sh"
  "scripts/control-panel.sh"
  "scripts/start-pipeline.sh"
  "scripts/tmux-layout.sh"
  "scripts/setup.sh"
  "scripts/update.sh"
  ".github/workflows/kiro-review.yml"
  ".kiro/agents/code-reviewer.json"
  "justfile"
  "skills-lock.json"
)

updated=0
for f in "${TARGETS[@]}"; do
  if [ -f "${SRC}/${f}" ]; then
    mkdir -p "$(dirname "$f")"
    if [ -f "$f" ] && diff -q "$f" "${SRC}/${f}" >/dev/null 2>&1; then
      continue
    fi
    cp "${SRC}/${f}" "$f"
    echo "  ✅ ${f}"
    updated=$((updated + 1))
  fi
done

# Update skills (symlinks — only add new ones)
if [ -d "${SRC}/.kiro/skills" ]; then
  for skill in "${SRC}"/.kiro/skills/*/; do
    name=$(basename "$skill")
    if [ ! -e ".kiro/skills/${name}" ]; then
      cp -r "$skill" ".kiro/skills/${name}"
      echo "  ✅ .kiro/skills/${name} (new)"
      updated=$((updated + 1))
    fi
  done
fi

echo ""
if [ "$updated" -eq 0 ]; then
  echo "✨ 最新の状態です。"
else
  echo "✨ ${updated} ファイルを更新しました。"
  echo ""
  read -r -p "  この変更をコミットしますか？ (Y/n) → " yn
  if [ "$yn" != "n" ] && [ "$yn" != "N" ]; then
    git add -A
    git commit -m "chore: update kiro-engineer-teams pipeline"
    echo "  ✔ コミットしました。"
    read -r -p "  プッシュしますか？ (Y/n) → " yn2
    if [ "$yn2" != "n" ] && [ "$yn2" != "N" ]; then
      git push --no-verify
      echo "  ✔ プッシュしました。"
    fi
  fi
fi
