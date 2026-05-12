<div align="center">

# 🏭 ai-engineer-teams

**動的スケーリング型エージェント開発パイプライン**
**[Kiro CLI](https://kiro.dev/docs/cli/) × [zellij](https://zellij.dev/)**

issue → 実装 → レビュー → マージ → E2E検証を全自動化。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../LICENSE)
[![Kiro CLI](https://img.shields.io/badge/Kiro_CLI-compatible-purple.svg)](https://kiro.dev/docs/cli/)
[![CI + Kiro Review](https://img.shields.io/badge/CI-Kiro_Review-green.svg)](../.github/workflows/kiro-review.yml)

[English](../README.md) · **日本語**

</div>

---

## クイックスタート

**1. プロジェクトディレクトリを作成してテンプレートをクローン**
```bash
mkdir <your-project>
cd <your-project>
git clone https://github.com/yoshimi-I/ai-engineer-teams.git .
```

**2. 前提ツールをインストール**
```bash
just setup
```

**3. 起動（リポジトリ作成 → INCEPTION → パイプライン）**
```bash
just start
```

`just start` は既存の INCEPTION 成果物があればそこから継続します。
`just restart` は AI-DLC / INCEPTION 成果物を残したまま、ローカルのエージェント実行状態だけを消して、AI-DLC 後の最初のパイプラインサイクルから再開します。

> 💡 GitHubの **「Use this template」** ボタンから直接リポジトリを作成することもできます。

---

## 📥 既存プロジェクトへの導入

既にプロジェクトがある場合、プロジェクトルートでこのワンライナーを実行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yoshimi-I/ai-engineer-teams/main/scripts/install.sh)
```

`.kiro/`、`scripts/`、`justfile`、`AGENTS.md`、`skills-lock.json` がコピーされます。既存ファイルは上書きされません。

その後：
```bash
just setup   # 前提ツールをインストール
just start   # INCEPTION + パイプライン起動
```

---

## 🔄 全体フロー

```
./scripts/start-pipeline.sh
│
├── Phase 1: INCEPTION（あなた + AI）
│   ├── 1. ワークスペース検出 — 既存コードをスキャン
│   ├── 2. 要件分析 — 何を作るか明確化
│   ├── 3. ユーザーストーリー — ユーザー行動を定義（必要時）
│   ├── 4. アーキテクチャ設計 — 技術スタック + 構成（必要時）
│   └── 5. Issue生成 — GitHub issueを自動作成
│
└── Phase 2: 自律パイプライン（zellij）
    │
    └── オーケストレーター（最小構成で起動 → 必要に応じてスケール）
        │
        ├── issue検出 → implement pane を追加（AI planner が依存関係を見て数を判断）
        ├── 承認済みPR検出 → review pane を追加（merge-manager専用）
        ├── レビュー指摘/conflict検出 → fix-review pane を追加
        ├── merge検出 → e2e-hunt / ui-audit を追加
        └── watch-main / improve → 環境変数で有効化した場合のみ追加
```

Phase 1はあなたの入力が必要です。Phase 2は完全自動 — エージェントはissue/PRが来るまで待機し、検出次第動き始めます。

---

## 🖥️ Zellij タブ構成

| タブ | キー | 内容 |
|------|-----|------|
| **Pipeline** | Prefix+1 | Orchestrator / Progress Report / Control Panel / Operator |
| **Agents** | Prefix+2 | 動的 pane がここに作成される |

### 動的 pane（必要な時だけ作成される）

| アイコン | ロール | 起動条件 |
|---------|-------|---------|
| 🖥️ | dev-server | `package.json` 等が存在し、ブラウザ/E2E系エージェントが必要な時 |
| 🔨 | implement | ready issue があり、依存関係がクリアな時（複数起動可能） |
| 🔍 | review | `APPROVED` かつ `develop` 宛の PR がある時（merge-manager専用） |
| 🔧 | fix-review | `changes_requested` / `conflict` / CI失敗の PR がある時 |
| 🧪 | e2e-bug-hunt | merge検出後、dev-server稼働時 |
| 🎨 | ui-audit | merge検出後、dev-server稼働時（`ORCH_AUTO_UI_AUDIT=false`で無効化） |
| 👀 | watch-main | 常駐（`ORCH_AUTO_WATCH_MAIN=false`で無効化） |
| 💡 | improve | `ORCH_AUTO_IMPROVE=true` で有効化した場合のみ |

各 pane は issue/PR の発生を待機し、検出次第起動します。AI planner が pane 数を決め、Bash がフォールバックとして依存関係ベースでスケーリングします。

### キーバインド

| キー | 操作 |
|------|------|
| `Ctrl+b` then `1/2` | タブ切り替え（Pipeline / Agents） |
| マウスクリック | ペインにフォーカス |

---

## 🏗️ アーキテクチャ

```
GitHub Issue
    │
    ▼
Orchestrator（最小構成で起動 → 必要に応じてスケール）
    │
    ├── implement pane ×N → issue実装 → PR
    │   （AI plannerが依存関係・conflict可能性・稼働paneから pane数を判断）
    │                                │
    │                    CI: konippi/kiro-cli-review-action（厳格レビュー）
    │                                │
    │                         ┌──────┴──────┐
    │                      🟢 APPROVE    🔴 REQUEST_CHANGES
    │                         │              │
    │                    CI: Auto Merge  fix-review pane
    │                                    修正 → 再push
    │                         │
    │                    developにマージ
    │                         │
    ├── watch-main → 常駐: develop監視 → E2E → main昇格
    ├── e2e-bug-hunt → merge検出時のPlaywright巡回 → bug issue作成
    ├── ui-audit → merge検出時のデザイン品質監査 → design-review issue作成
    ├── dev-server → package.json等があれば自動起動
    └── improve → ORCH_AUTO_IMPROVE=true のとき改善issue生成
```

> 全エージェントはGitHub issueのassigneeで排他制御し、`issue/task.md` を補助記録として併用します。
> コードレビューはCI側に委譲し、ローカル `review` はmerge-manager専用に徹します。

---

## 📋 前提条件

| ツール | インストール | 必須 |
|--------|------------|------|
| [Kiro CLI](https://kiro.dev/docs/cli/) | [ダウンロード](https://kiro.dev/downloads/) | ✅ |
| [zellij](https://zellij.dev/) | `brew install zellij` | ✅ 0.44.1+ |
| [GitHub CLI](https://cli.github.com/) | `brew install gh` → `gh auth login` | ✅ |
| [just](https://just.systems/) | `brew install just` | 任意（GitLab切替用） |

zellij は **0.44.1 以上が必須**です。オーケストレーターは新しい CLI automation API（`list-panes --json`、pane ID、`--tab-id`、`--close-on-exit`）に依存しています。`0.43.1` など古いバージョンでは、必要な時だけ pane を作り、完了後に閉じる動的ライフサイクルが正しく動きません。

```bash
zellij --version
brew upgrade zellij
```

オーケストレーターはデフォルトで AI Planner prompt（`.kiro/prompts/orchestrator-plan.md`）を使います。Bash が GitHub issue、PR、pane、project、post-merge 状態を集め、Planner に JSON の起動計画だけを作らせ、その JSON を検証してから zellij pane を起動します。Planner は `dev-server`、`implement`、`review`、`fix-review`、`e2e`、`e2e-bug-hunt`、`ui-audit`、`watch-main`、`improve` のどれを起動するかを判断します。`implement` pane の数は、依存関係・変更ファイルの衝突可能性・稼働中pane・レビュー/E2E状況を見て Planner が判断します。`blocked` ラベル付き、または open な `depends-on: #N` 依存を持つ issue は ready とみなしません。AI 計画に失敗した場合のみ、Bash が依存関係を見たスケーリングにフォールバックします。

`just preflight` で、ローカルツール、GitHub認証、branch構成、Actions権限、review secret、workflow、E2Eコマンド検出を起動前に診断できます。

`watch-main` は develop から main への昇格監視としてデフォルトで常駐します。無効化する場合は `ORCH_AUTO_WATCH_MAIN=false` を指定します。main昇格には実E2Eコマンド（`AI_E2E_COMMAND`、レガシー名 `KIRO_E2E_COMMAND`、`just e2e`、または `package.json` の `e2e`）が必須です。`ui-audit` は merge 後にデフォルトで自動起動し、`ORCH_AUTO_UI_AUDIT=false` で無効化できます。`improve` の自動起動は `ORCH_AUTO_IMPROVE=true` を指定した場合のみ有効です。AI Planner を無効化したい場合は `ORCH_AI=false` を指定します。

コードレビューは `develop` PR 上のレビューワークフロー（`konippi/kiro-cli-review-action` および `anthropics/claude-code-action`）に委譲します。ローカルの `review` pane は merge-manager 専用で、承認済みPRのCI待ち・squash merge・merge再試行だけを扱います。PRは `review_pending`、`approved_ready`、`approved_pending`、`changes_requested`、`conflict`、`approved_checks_failed`、`merge_blocked` に正規化され、planner と dashboard が同じ状態機械を見ます。

オーケストレーター画面は固定 tick（`ORCH_TICK_INTERVAL`、デフォルト `10s`）で更新され、最後の planner 種別、起動した action、skip 理由、次回 tick を表示します。同じ状態は `.agent-status/orchestrator.json` と `.agent-status/.cache/orchestrator_decision.json` にも書き出されます。

> **Linux**: `brew install` の代わりに各ツールのインストールドキュメントを参照。
> **Windows**: WSL2を使用するか、各ツールのWindowsインストールドキュメントを参照。

---

## 🛡️ 組み込みルール

steering ファイル（`.kiro/steering/development-rules.md`）が全エージェントの全ターンに適用するルール：

| カテゴリ | 主なルール |
|---------|-----------|
| **TDD** | Red → Green → Refactor。テストなしでコードを書かない。 |
| **テスト** | 3層: Unit（関数ごと）+ Integration（APIごと）+ E2E（ユーザーフローごと） |
| **PRゲート** | Unit + Integration + E2E 全通過必須。テスト不足 = マージ不可。 |
| **エラー処理** | 統一APIエラーフォーマット。行動可能なメッセージ。リソースクリーンアップ。 |
| **API設計** | フロント↔バック型定義を常に同期。両端でバリデーション。 |
| **Git** | worktree隔離。Conventional Commits（英語）。squash mergeのみ。 |
| **セキュリティ** | シークレット禁止。入力検証。パラメータ化クエリ。最小権限。 |
| **パフォーマンス** | N+1禁止。ループ内API禁止。不要な再レンダリング防止。 |
| **並列エージェント** | GitHub issueのassigneeで排他制御。`issue/task.md` は補助記録。 |

---

## 📁 ディレクトリ構成

```
.kiro/
├── steering/development-rules.md  # ルール（毎ターン自動適用）
├── skills/                        # リファレンス（必要時に参照）
│   ├── clean-ddd-hexagonal/       #   DDD + Clean Architecture
│   ├── frontend-design/           #   UI設計ガイド
│   ├── baseline-ui/               #   Tailwind制約
│   ├── fixing-accessibility/      #   アクセシビリティ
│   ├── fixing-metadata/           #   SEO/OGP
│   └── fixing-motion-performance/ #   アニメーション性能
├── prompts/                       # ワークフロー（/name で呼び出し）
│   ├── implement.md               #   issue → 実装 → PRループ
│   ├── review.md                  #   7視点厳格レビュー
│   ├── fix-review.md       #   レビュー指摘修正
│   ├── dev-server.md              #   開発サーバー常駐
│   ├── watch-main.md              #   develop監視 → E2E → main昇格
│   ├── e2e-bug-hunt.md            #   Playwright巡回
│   ├── ui-audit.md                #   デザイン品質監査
│   ├── improve.md                 #   改善issue自動生成
│   ├── 8-agent-pipeline.md        #   パイプライン構成ガイド
│   └── ...                        #   brainstorming, pr 等
└── agents/default.json            # エージェント設定
scripts/
├── start-pipeline.sh              # 起動スクリプト
├── agent.sh                       # エージェントラッパー
└── pipeline.kdl                   # zellijレイアウト
```

---

## 🔄 Steering / Skills / Prompts の違い

| | Steering | Skills | Prompts |
|---|:---:|:---:|:---:|
| **ロード** | 毎ターン全文 | メタデータのみ → 必要時にフル | `/name` で全文送信 |
| **確実性** | 100% | エージェント判断 | 100% |
| **用途** | ルール・規約 | リファレンス知識 | タスクの手順書 |

---

## 🔧 カスタマイズ

```bash
# 不要なスキルを削除
rm -rf .kiro/skills/clean-ddd-hexagonal

# 不要なプロンプトを削除
rm .kiro/prompts/improve.md

# 追加
mkdir .kiro/skills/my-guide       # + SKILL.md（frontmatter必須）
touch .kiro/prompts/my-workflow.md

# 言語切り替え
# /to-japanese — プロンプト・steeringを日本語に
# /to-english  — プロンプト・steeringを英語に
```

**GitLabの場合:**
```bash
just to-gitlab   # gh → glab
just to-github   # 元に戻す
```

---

<div align="center">

[MIT](../LICENSE) © [yoshimi-I](https://github.com/yoshimi-I)

</div>
