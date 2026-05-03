#!/usr/bin/env bash
# 8-Agent Pipeline Launcher
#
# Phase 1: INCEPTION — structured planning with AI-DLC workflow
# Phase 2: Pipeline — launch 8 agents in zellij
#
# Usage: ./scripts/start-pipeline.sh

set -euo pipefail

# ── Preflight ──
for cmd in kiro-cli zellij gh; do
  if ! command -v "$cmd" &>/dev/null; then
    echo "❌ Required: $cmd"
    exit 1
  fi
done

# ── KIRO_API_KEY Secret check ──
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
  read -p "  KIRO_API_KEY を入力 (空でスキップ): " KIRO_KEY
  if [[ -n "$KIRO_KEY" ]]; then
    echo "$KIRO_KEY" | gh secret set KIRO_API_KEY
    echo "  ✔ KIRO_API_KEY を設定しました。"
  else
    echo "  ⏭️  スキップ。後で設定: gh secret set KIRO_API_KEY"
  fi
  echo ""
fi

if [[ ! -d ".kiro/prompts" ]]; then
  echo "❌ Run from project root (no .kiro/prompts/ found)"
  exit 1
fi

if ! git remote get-url origin &>/dev/null; then
  echo "❌ git remote 'origin' is not configured"
  echo "   Run: git remote add origin <repo-url>"
  exit 1
fi

# ── Check if this is the template repo itself ──
REMOTE_URL=$(git remote get-url origin 2>/dev/null || echo "")
if echo "$REMOTE_URL" | grep -q "kiro-engineer-teams"; then
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "  ⚠️  テンプレートリポジトリを直接使用しています"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""
  echo "  新しいプロジェクト用のリポジトリを作成しますか？"
  echo ""
  read -p "  リポジトリ名を入力 (空でスキップ): " REPO_NAME
  if [[ -n "$REPO_NAME" ]]; then
    read -p "  公開設定 (1: private, 2: public) [1]: " VISIBILITY
    VIS_FLAG="--private"
    [[ "$VISIBILITY" == "2" ]] && VIS_FLAG="--public"

    echo ""
    echo "  📦 リポジトリを作成中: ${REPO_NAME}"

    # Remove template-only files before pushing
    rm -f LICENSE
    rm -rf docs
    for f in README.md AGENTS.md; do
      grep -q "kiro-engineer-teams" "$f" 2>/dev/null && rm -f "$f"
    done
    git add -A
    git commit -m "init: scaffold from kiro-engineer-teams" --allow-empty 2>/dev/null || true

    gh repo create "$REPO_NAME" $VIS_FLAG --source=. --push
    echo "  ✔ リポジトリを作成しました: $(gh repo view --json url --jq '.url')"
    echo ""
  fi
fi

if ! gh auth status &>/dev/null; then
  echo "❌ GitHub CLI is not authenticated"
  echo "   Run: gh auth login"
  exit 1
fi

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
  ISSUE_COUNT=$(gh issue list --state open --json number --jq 'length' 2>/dev/null || echo "0")
  if [[ "$ISSUE_COUNT" -gt 0 ]]; then
    INCEPTION_DONE=true
  fi
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
  read -p "  Enter を押して開始 → " _

  kiro-cli chat --trust-all-tools "/inception"

  # ── Push INCEPTION artifacts to main ──
  INCEPTION_FILES=$(git ls-files --others --modified -- aidlc-docs/ issue/ .kiro/steering/ 2>/dev/null)
  if [[ -n "$INCEPTION_FILES" ]]; then
    echo ""
    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    echo "  INCEPTION 成果物を検出:"
    echo "$INCEPTION_FILES" | sed 's/^/    /'
    echo ""
    read -p "  main にプッシュしてエージェントがアクセスできるようにしますか？ (Y/n) → " yn
    if [[ "$yn" != "n" && "$yn" != "N" ]]; then
      git add aidlc-docs/ issue/ .kiro/steering/
      git commit -m "docs: add INCEPTION artifacts"
      git push origin main
      echo "  ✔ main にプッシュしました。"
    else
      for pattern in aidlc-docs/ issue/; do
        grep -qxF "$pattern" .gitignore 2>/dev/null || echo "$pattern" >> .gitignore
      done
      echo "  ✔ aidlc-docs/ と issue/ を .gitignore に追加しました。"
    fi
  fi

  ISSUE_COUNT=$(gh issue list --state open --json number --jq 'length' 2>/dev/null || echo "0")
fi

# ── Check issues exist ──
if [[ -z "${ISSUE_COUNT:-}" ]]; then
  ISSUE_COUNT=$(gh issue list --state open --json number --jq 'length' 2>/dev/null || echo "0")
fi
if [[ "$ISSUE_COUNT" -eq 0 ]]; then
  echo ""
  echo "⚠️  オープンな issue がありません。"
  read -p "  それでもパイプラインを起動しますか？ (y/N) → " yn
  [[ "$yn" != "y" && "$yn" != "Y" ]] && echo "中止しました。" && exit 0
fi

# ── Phase 2: Pipeline ──
echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  フェーズ 2: 12エージェント パイプライン"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""
echo "  📋 オープンissue: ${ISSUE_COUNT}件"
echo ""
echo "  🎭 オーケストレーター → 状況に応じて12paneに役割を動的割り当て"
echo "  🖥️  Dev-Server       → 開発サーバーの起動・維持"
echo "  🔨 Impl ×N          → issueを取得して実装 → PR作成"
echo "  🔍 CI Kiro Review   → PRの自動コードレビュー"
echo "  🔧 Fix-Review ×N    → レビュー指摘の自動修正"
echo "  👀 Watch-Main       → マージ後のE2E検証"
echo "  🧪 E2E-Hunt         → Playwright巡回テスト"
echo "  💡 Improve          → 改善issueの自動生成"
echo ""
echo "  各エージェントは仕事を待機し、自動で開始します。"
echo ""

# Generate layout with project cwd
LAYOUT_TMP=$(mktemp /tmp/pipeline-XXXXXX.kdl)
sed "s|__PROJECT_CWD__|$(pwd)|g" scripts/pipeline.kdl > "$LAYOUT_TMP"
trap 'rm -f "$LAYOUT_TMP"' EXIT

zellij --layout "$LAYOUT_TMP"
