#!/usr/bin/env bash
# AI Engineer Teams Pipeline Launcher
#
# Phase 1: INCEPTION — structured planning with AI-DLC workflow
# Phase 2: Pipeline — launch agents in zellij
#
# Usage: ./scripts/start-pipeline.sh

set -euo pipefail

INTEGRATION_BRANCH="${AI_INTEGRATION_BRANCH:-${KIRO_INTEGRATION_BRANCH:-develop}}"
STABLE_BRANCH="${AI_STABLE_BRANCH:-${KIRO_STABLE_BRANCH:-main}}"
export AI_INTEGRATION_BRANCH="$INTEGRATION_BRANCH"
export AI_STABLE_BRANCH="$STABLE_BRANCH"
export KIRO_INTEGRATION_BRANCH="$INTEGRATION_BRANCH"
export KIRO_STABLE_BRANCH="$STABLE_BRANCH"

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/runner.sh
source "${SCRIPT_DIR}/lib/runner.sh"

# ── Preflight ──
RUNNER_BIN="$(ai_runner_binary)"
for cmd in "$RUNNER_BIN" zellij gh jq; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Required: $cmd"
    exit 1
  fi
done

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

ZELLIJ_VERSION=$(zellij --version | awk '{print $2}')
if ! version_ge "$ZELLIJ_VERSION" "0.44.1"; then
  echo "❌ Required: zellij >= 0.44.1 (found ${ZELLIJ_VERSION})"
  echo "   Dynamic pane orchestration requires the latest zellij CLI automation."
  exit 1
fi

# ── KIRO_API_KEY Secret check ──
check_kiro_api_key() {
  echo "🔑 KIRO_API_KEY チェック..."
  if gh secret list 2>/dev/null | grep -q "KIRO_API_KEY"; then
    echo "✅ KIRO_API_KEY 設定済み"
  else
    echo ""
    echo "  ⚠️  KIRO_API_KEY が GitHub Secrets に未設定です。"
    echo "  CI の Kiro Review (konippi/kiro-cli-review-action) に必要です。"
    echo ""
    echo "  取得先: https://app.kiro.dev → API Keys"
    echo ""
    read -r -p "  KIRO_API_KEY を入力 (空でスキップ): " KIRO_KEY
    if [[ -n "$KIRO_KEY" ]]; then
      echo "$KIRO_KEY" | gh secret set KIRO_API_KEY
      echo "  ✔ KIRO_API_KEY を設定しました。"
    else
      echo "  ⏭️  スキップ。後で設定: gh secret set KIRO_API_KEY"
    fi
    echo ""
  fi
}

publish_inception_artifacts() {
  local branch="docs/inception-artifacts"
  local current_branch

  current_branch="$(git branch --show-current)"
  if [[ "$current_branch" == "$STABLE_BRANCH" || "$current_branch" == "$INTEGRATION_BRANCH" ]]; then
    branch="${branch}-$(date +%Y%m%d%H%M%S)"
    git switch -c "$branch"
  else
    branch="$current_branch"
  fi

  # issue/task.md is intentionally excluded: it is a LOCAL auxiliary tracker
  # (see .gitignore and .kiro/steering/development-rules.md). The source of
  # truth for issue assignment is GitHub itself (assignee-based mutex).
  # Pushing task.md would create merge conflicts between parallel agents and
  # duplicate state already queryable via `gh issue list`.
  git add -f aidlc-docs/ .kiro/steering/
  git commit -m "docs: add INCEPTION artifacts"
  git push -u origin "$branch"

  if gh pr view "$branch" &>/dev/null; then
    echo "  ✔ 既存PRを更新しました: $(gh pr view "$branch" --json url --jq '.url')"
  else
    gh pr create \
      --head "$branch" \
      --base "$INTEGRATION_BRANCH" \
      --title "docs: add INCEPTION artifacts" \
      --body "Add INCEPTION artifacts (requirements / stories / design vision / architecture) so pipeline agents can access the project plan. issue/task.md is intentionally kept local — GitHub issue assignees are the source of truth for the parallel agent mutex."
    echo "  ✔ PRを作成しました: $(gh pr view "$branch" --json url --jq '.url')"
  fi
}

ensure_integration_branch() {
  if git ls-remote --exit-code --heads origin "$INTEGRATION_BRANCH" >/dev/null 2>&1; then
    return 0
  fi

  echo "🌿 integration branch '${INTEGRATION_BRANCH}' が未作成です。"
  echo "   ${STABLE_BRANCH} から作成して push します。"
  git fetch origin "$STABLE_BRANCH" --quiet
  git push origin "refs/remotes/origin/${STABLE_BRANCH}:refs/heads/${INTEGRATION_BRANCH}"
}

if [[ ! -d ".kiro/prompts" ]]; then
  echo "❌ Run from project root (no .kiro/prompts/ found)"
  exit 1
fi

if ! git remote get-url origin &>/dev/null; then
  echo "❌ git remote 'origin' is not configured"
  echo "   Run: git remote add origin <repo-url>"
  exit 1
fi

# ── Check if this is the upstream template repo itself ──
# We only trigger the scaffold-new-repo flow when the origin URL matches the
# canonical upstream repository exactly. Matching on the substring
# "ai-engineer-teams" would also fire for forks and unrelated repos that
# happen to contain the same string in their URL (e.g. myorg/ai-engineer-teams-playground).
# That misfire would delete LICENSE / docs / README and replace origin — highly
# destructive on a fork.
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
UPSTREAM_TEMPLATE_REGEX='(^|[:/])yoshimi-I/ai-engineer-teams(\.git)?/?$'
IS_UPSTREAM_TEMPLATE=false
if [[ "$REMOTE_URL" =~ $UPSTREAM_TEMPLATE_REGEX ]]; then
  IS_UPSTREAM_TEMPLATE=true
fi

if [[ "$IS_UPSTREAM_TEMPLATE" == "true" ]]; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ⚠️  アップストリームテンプレートリポジトリを直接使用しています"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  origin: $REMOTE_URL"
  echo ""
  echo "  このまま進めると、新しいプロジェクト用のリポジトリを作成し、"
  echo "  origin を差し替えます。LICENSE / docs / README (テンプレ由来) も削除されます。"
  echo ""
  read -r -p "  新しいプロジェクトを作成しますか？ (y/N) → " CONFIRM
  if [[ "$CONFIRM" != "y" && "$CONFIRM" != "Y" ]]; then
    echo "  中止しました。origin を自分のプロジェクトに変更してから再実行してください:"
    echo "    git remote set-url origin <your-repo-url>"
    exit 0
  fi

  DEFAULT_REPO="$(basename "$PWD")"
  read -r -p "  リポジトリ名 (${DEFAULT_REPO}): " REPO_NAME
  REPO_NAME="${REPO_NAME:-$DEFAULT_REPO}"
  {
    read -r -p "  公開設定 (1: private, 2: public) [1]: " VISIBILITY
    VIS_FLAG="--private"
    [[ "$VISIBILITY" == "2" ]] && VIS_FLAG="--public"

    echo ""
    echo "  📦 リポジトリを作成中: ${REPO_NAME}"

    # Remove template-only files before pushing
    rm -f LICENSE
    rm -rf docs
    for f in README.md AGENTS.md; do
      grep -q "ai-engineer-teams" "$f" 2>/dev/null && rm -f "$f"
    done

    # Wipe the template's git history so the new project starts from a single
    # clean commit. Without this, the template's ~230+ commits (every fix,
    # refactor, and test iteration we shipped upstream) would all be pushed
    # into the user's brand-new repo, producing a confusing first-day log
    # full of unrelated messages. See init.sh for the same pattern.
    rm -rf .git
    git init -q -b "$STABLE_BRANCH" 2>/dev/null || { git init -q && git symbolic-ref HEAD "refs/heads/${STABLE_BRANCH}"; }
    git add -A
    INIT_AUTHOR_NAME="$(git config --global user.name 2>/dev/null || echo 'kiro')"
    INIT_AUTHOR_EMAIL="$(git config --global user.email 2>/dev/null || echo 'kiro@localhost')"
    GIT_AUTHOR_NAME="$INIT_AUTHOR_NAME" \
    GIT_AUTHOR_EMAIL="$INIT_AUTHOR_EMAIL" \
    GIT_COMMITTER_NAME="$INIT_AUTHOR_NAME" \
    GIT_COMMITTER_EMAIL="$INIT_AUTHOR_EMAIL" \
      git commit -q -m "init: scaffold from ai-engineer-teams" --allow-empty

    # Create the remote repo and push the single init commit.
    gh repo create "$REPO_NAME" $VIS_FLAG --source=. --remote origin --push
    echo "  ✔ リポジトリを作成しました: $(gh repo view --json url --jq '.url')"
    echo ""
  }
fi

if ! gh auth status &>/dev/null; then
  echo "❌ GitHub CLI is not authenticated"
  echo "   Run: gh auth login"
  exit 1
fi

./scripts/preflight.sh

# Check API key on the actual target repo (after potential repo creation)
check_kiro_api_key
ensure_integration_branch

# ── Ensure directories ──
mkdir -p issue aidlc-docs/inception

if [[ ! -f "issue/task.md" ]]; then
  cat > issue/task.md << 'TMPL'
# Issue Tracker

| Issue | Title | Status | Branch |
|-------|-------|--------|--------|
| #999 | (example) feat: add feature | in-progress / in-review / merged / resolved | feat/issue-999-xxx |
TMPL
fi

# ── Phase 1: INCEPTION (skip if already completed) ──
INCEPTION_DONE=false
if [[ -d "aidlc-docs/inception" ]] && ls aidlc-docs/inception/*/*.md &>/dev/null 2>&1; then
  INCEPTION_DONE=true
  ISSUE_COUNT=$(gh issue list --state open --limit 500 --json number --jq 'length' 2>/dev/null || echo "0")
fi

if [[ "$INCEPTION_DONE" == "true" ]]; then
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ✅ INCEPTION 完了済み"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  📄 成果物: aidlc-docs/inception/"
  echo "  📋 オープンissue: ${ISSUE_COUNT}件"
  echo ""
  echo "  INCEPTION をスキップ → パイプラインを直接起動します。"
  echo ""
else
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  フェーズ 1: INCEPTION (AI-DLC)"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  Kiro CLI で INCEPTION ワークフローを開始します。"
  echo "  以下のステップを順に進めます:"
  echo ""
  echo "    1. ワークスペース検出"
  echo "    2. 要件分析"
  echo "    3. ユーザーストーリー（必要に応じて）"
  echo "    4. アーキテクチャ設計（必要に応じて）"
  echo "    5. Issue 自動生成"
  echo ""
  echo "  ⚠️  INCEPTION が完了したら /quit と入力してこの画面を抜けてください。"
  echo "      パイプラインが自動で起動します。"
  echo ""
  read -r -p "  Enter を押して開始 → " _

  ai_run_interactive "/inception"

  # ── Publish INCEPTION artifacts through a PR ──
  # issue/ is intentionally excluded: task.md is a local auxiliary tracker
  # (already in .gitignore). GitHub issue assignees are the single source
  # of truth for the parallel agent mutex. Pushing task.md would cause
  # merge churn between agent worktrees.
  INCEPTION_FILES=$(git ls-files --others --modified -- aidlc-docs/ .kiro/steering/ 2>/dev/null)
  if [[ -n "$INCEPTION_FILES" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  INCEPTION 成果物を検出:"
    while IFS= read -r file; do
      echo "    ${file}"
    done <<< "$INCEPTION_FILES"
    echo ""
    read -r -p "  PRを作成してエージェントが成果物をレビューできるようにしますか？ (Y/n) → " yn
    if [[ "$yn" != "n" && "$yn" != "N" ]]; then
      publish_inception_artifacts
      echo "  PRをマージ後、もう一度 ./scripts/start-pipeline.sh を実行してください。"
      exit 0
    else
      # Ensure aidlc-docs/ stays local if the user declined the PR.
      # issue/task.md is already gitignored via the repository default.
      grep -qxF "aidlc-docs/" .gitignore 2>/dev/null || echo "aidlc-docs/" >> .gitignore
      echo "  ✔ aidlc-docs/ を .gitignore に追加しました (issue/task.md は既にローカル保持)。"
    fi
  fi

  ISSUE_COUNT=$(gh issue list --state open --limit 500 --json number --jq 'length' 2>/dev/null || echo "0")
fi

# ── Check issues exist ──
if [[ -z "${ISSUE_COUNT:-}" ]]; then
  ISSUE_COUNT=$(gh issue list --state open --limit 500 --json number --jq 'length' 2>/dev/null || echo "0")
fi
if [[ "$ISSUE_COUNT" -eq 0 ]]; then
  echo ""
  echo "⚠️  オープンな issue がありません。"
  read -r -p "  それでもパイプラインを起動しますか？ (y/N) → " yn
  [[ "$yn" != "y" && "$yn" != "Y" ]] && echo "中止しました。" && exit 0
fi

# ── Phase 2: Pipeline ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  フェーズ 2: エージェント パイプライン"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
  echo "  📋 オープンissue: ${ISSUE_COUNT}件"
  echo ""
  echo "  🎭 オーケストレーター → Pipeline tabに固定表示"
  echo "  💬 Operator tab     → ユーザー確認・手動指示用の常駐チャット"
  echo "  🧩 Agents tab       → 動的paneはここだけに作成"
  echo "  🖥️  Dev-Server       → E2E/監視が必要な時に開発サーバーを起動"
echo "  🔨 Impl             → AIがready issueを見てpane数を判断 → PR作成"
echo "  🔍 Review           → PRレビュー/マージ判断（CIレビューと分担）"
echo "  🔧 Fix-Review       → レビュー指摘の自動修正"
echo "  🧪 E2E              → 必要時のブラウザ検証"
echo "  👀 Watch-Main       → 常駐: develop監視 → E2E → main昇格"
echo "  🐞 E2E-Hunt         → merge検出時のPlaywright巡回 → bug issue作成"
echo "  🎨 UI-Audit         → merge検出時のデザイン品質監査 → design-review issue作成"
echo ""
echo "  通常PRは ${INTEGRATION_BRANCH} に統合し、E2E通過後に ${STABLE_BRANCH} へ昇格します。"
echo "  AI plannerが依存関係・PR状態・E2E要否を見てpane数と役割を決めます。"
echo "  watch-main/ui-audit は ORCH_AUTO_WATCH_MAIN=false / ORCH_AUTO_UI_AUDIT=false で無効化できます。"
echo "  improve の自動起動は ORCH_AUTO_IMPROVE=true で有効化できます。"
echo ""

LAYOUT_TMP=$(mktemp /tmp/pipeline-XXXXXXXX).kdl
sed "s|__PROJECT_CWD__|$(pwd)|g" scripts/pipeline.kdl > "$LAYOUT_TMP"
trap 'rm -f "$LAYOUT_TMP"' EXIT

zellij --layout "$LAYOUT_TMP"
