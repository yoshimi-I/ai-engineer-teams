<div align="center">

# 🏭 kiro-engineer-teams

**10エージェント並列開発パイプライン**
**[Kiro CLI](https://kiro.dev/docs/cli/) × [zellij](https://zellij.dev/)**

issue → 実装 → レビュー → マージ → E2E検証を全自動化。

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](../LICENSE)
[![Kiro CLI](https://img.shields.io/badge/Kiro_CLI-compatible-purple.svg)](https://kiro.dev/docs/cli/)

[English](../README.md) · **日本語**

</div>

---

## クイックスタート

**1. プロジェクトディレクトリを作成してテンプレートをクローン**
```bash
mkdir <your-project>
cd <your-project>
git clone https://github.com/yoshimi-I/kiro-engineer-teams.git .
```

**2. 前提ツールをインストール**
```bash
just setup
```

**3. 起動（リポジトリ作成 → INCEPTION → パイプライン）**
```bash
just start
```

> 💡 GitHubの **「Use this template」** ボタンから直接リポジトリを作成することもできます。

---

## 📥 既存プロジェクトへの導入

既にプロジェクトがある場合、プロジェクトルートでこのワンライナーを実行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yoshimi-I/kiro-engineer-teams/main/scripts/install.sh)
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
└── Phase 2: 10エージェントパイプライン（完全自律）
    ├── Dev-Server → 開発サーバーを起動・常駐
    ├── Impl-1, Impl-2 → issueを拾って実装 → PR
    ├── Review-1, Review-2 → 7視点厳格レビュー → マージ
    ├── Fix-Review-1, Fix-Review-2 → レビュー指摘修正 → 再push
    ├── Watch-Main → マージ後E2E検証
    ├── E2E-Hunt → Playwright巡回 → バグissue
    └── Improve → 改善issue自動生成
```

Phase 1はあなたの入力が必要です。Phase 2は完全自動 — エージェントはissue/PRが来るまで待機し、検出次第動き始めます。

---

## 🚀 パイプライン起動

```bash
./scripts/start-pipeline.sh
```

<table>
<tr>
<td align="center">🖥️<br><b>Dev-Server</b><br><sub>サーバー常駐</sub></td>
<td align="center">🔨<br><b>Impl-1</b><br><sub>issue → 実装 → PR</sub></td>
<td align="center">🔨<br><b>Impl-2</b><br><sub>issue → 実装 → PR</sub></td>
</tr>
<tr>
<td align="center">🔍<br><b>Review-1</b><br><sub>PR → レビュー → マージ</sub></td>
<td align="center">🔍<br><b>Review-2</b><br><sub>PR → レビュー → マージ</sub></td>
<td align="center">🔧<br><b>Fix-Review-1</b><br><sub>指摘 → 修正 → push</sub></td>
</tr>
<tr>
<td align="center">🔧<br><b>Fix-Review-2</b><br><sub>指摘 → 修正 → push</sub></td>
<td align="center">👀<br><b>Watch-Main</b><br><sub>main監視 → E2E</sub></td>
<td align="center">🧪<br><b>E2E-Hunt</b><br><sub>Playwright巡回</sub></td>
</tr>
<tr>
<td align="center" colspan="3">💡<br><b>Improve</b><br><sub>改善issue生成</sub></td>
</tr>
</table>

各エージェントはissue/PRの発生を待機し、検出次第動き始めます。

### キーバインド

| キー | 操作 |
|------|------|
| `Ctrl+b` then `1/2/3` | ウィンドウ切り替え（Pipeline / Control / Kiro） |
| マウスクリック | ペインにフォーカス |

---

## 🏗️ アーキテクチャ

```
GitHub Issue
    │
    ▼
Agent 1,2: /implement ──→ PR作成（pre-commitでlint/test通過済み）
                           │
                           ▼
                     Agent 3,4: /review
                           │
                      ┌────┴────┐
                   🟢 LGTM   🔴 修正必須
                      │         │
                      ▼         ▼
                 マージ    Agent 5,6: /fix-review
                      │
                      ▼
                 mainにマージ
                      │
                      ▼
                 Agent 7: /watch-main（E2E検証）
                      │
                 バグ発見? → issue作成 → Agent 1,2 が拾う
                                        ▲
                                        │
                   Agent 8: /e2e-bug-hunt（Playwright巡回）

Agent 9: /improve（改善issue自動生成、10分間隔）
Agent 10: /dev-server（開発サーバー常駐）
```

> 全エージェントはGitHub issueのassigneeで排他制御し、`issue/task.md` を補助記録として併用します。

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

オーケストレーターはデフォルトで AI Planner prompt（`.kiro/prompts/orchestrator-plan.md`）を使います。Bash が GitHub issue、PR、pane、project、post-merge 状態を集め、Planner に JSON の起動計画だけを作らせ、その JSON を検証してから zellij pane を起動します。Planner は `dev-server`、`implement`、`review`、`fix-review`、`e2e`、`e2e-bug-hunt`、`watch-main`、`improve` のどれを起動するかを判断します。`implement` pane の数は、依存関係・変更ファイルの衝突可能性・稼働中pane・レビュー/E2E状況を見て Planner が判断します。`blocked` ラベル付き、または open な `depends-on: #N` 依存を持つ issue は ready とみなしません。AI 計画に失敗した場合のみ、Bash が依存関係を見たスケーリングにフォールバックします。

`watch-main` と `improve` の自動起動は `ORCH_AUTO_WATCH_MAIN=true` / `ORCH_AUTO_IMPROVE=true` を指定した場合のみ有効です。AI Planner を無効化したい場合は `ORCH_AI=false` を指定します。

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
│   ├── watch-main.md              #   main監視 → E2E
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
