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

# Files to update (overwrite) — update.sh is excluded and handled last
TARGETS=(
  ".github/workflows/kiro-review.yml"
  ".github/workflows/promote-main.yml"
  ".github/PULL_REQUEST_TEMPLATE.md"
  ".github/ISSUE_TEMPLATE/bug_report.md"
  ".github/ISSUE_TEMPLATE/feature_request.md"
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

# Sync entire directories via wildcard
for dir in scripts scripts/lib .kiro/prompts .kiro/skills .kiro/agents; do
  [ -d "${SRC}/${dir}" ] || continue
  mkdir -p "$dir"
  while IFS= read -r src_file; do
    rel="${src_file#"${SRC}"/}"
    # Skip update.sh itself (handled last for self-update)
    [ "$rel" = "scripts/update.sh" ] && continue
    mkdir -p "$(dirname "$rel")"
    if [ -f "$rel" ] && diff -q "$rel" "$src_file" >/dev/null 2>&1; then
      continue
    fi
    cp "$src_file" "$rel"
    echo "  ✅ ${rel}"
    updated=$((updated + 1))
  done < <(find "${SRC}/${dir}" -maxdepth 1 -type f | sort)
done

# Update steering defaults only when project-specific settings are still empty.
STEERING_SRC="${SRC}/.kiro/steering/development-rules.md"
STEERING_DST=".kiro/steering/development-rules.md"
if [ -f "$STEERING_SRC" ]; then
  mkdir -p "$(dirname "$STEERING_DST")"
  if [ ! -f "$STEERING_DST" ]; then
    cp "$STEERING_SRC" "$STEERING_DST"
    echo "  ✅ ${STEERING_DST}"
    updated=$((updated + 1))
  elif grep -q "# INCEPTION完了後に記入:" "$STEERING_DST"; then
    if ! diff -q "$STEERING_DST" "$STEERING_SRC" >/dev/null 2>&1; then
      cp "$STEERING_SRC" "$STEERING_DST"
      echo "  ✅ ${STEERING_DST} (template settings still empty)"
      updated=$((updated + 1))
    fi
  else
    echo "  ⏭️  ${STEERING_DST} (project-specific settings preserved)"
  fi
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
    git commit --no-verify -m "chore: update kiro-engineer-teams pipeline"
    echo "  ✔ コミットしました。"
    read -r -p "  プッシュしますか？ (Y/n) → " yn2
    if [ "$yn2" != "n" ] && [ "$yn2" != "N" ]; then
      echo "  ↻ リモートの最新変更を取り込んでからプッシュします..."
      if git pull --rebase --autostash; then
        if git push --no-verify; then
          echo "  ✔ プッシュしました。"
        else
          echo "  ⚠️  push に失敗しました。手動で git status を確認してください。"
        fi
      else
        echo "  ⚠️  rebase に失敗しました。コンフリクトを解消してから git rebase --continue → git push --no-verify を実行してください。"
      fi
    fi
  fi
fi

# Self-update: copy update.sh LAST, after all logic has finished.
# This is safe because bash has already read and parsed everything above.
if [ -f "${SRC}/scripts/update.sh" ]; then
  if ! diff -q "scripts/update.sh" "${SRC}/scripts/update.sh" >/dev/null 2>&1; then
    cp "${SRC}/scripts/update.sh" "scripts/update.sh"
    echo "  ✅ scripts/update.sh (self-updated — run again to pick up changes)"
  fi
fi
