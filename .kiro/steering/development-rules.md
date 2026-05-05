---
name: development-rules
description: 全タスクに適用されるコアルール
---

## 言語

ユーザーへの応答は常に日本語で行うこと。以下は**全て英語**で書くこと:
- コード・コメント
- コミットメッセージ
- PRタイトル・PR本文（description）
- issueタイトル・issue本文
- PRレビューコメント・issueコメント
- `gh pr create --body` や `gh issue create --body` の引数

## 自律行動

ユーザーへの質問・確認・選択肢の提示は禁止。自分で判断して進めること。「どうしますか？」「どちらがいいですか？」のような質問で停止してはならない。

## 初期セットアップ

以下の「プロジェクト固有設定」セクションが空（コメントのみ）の場合:
1. `.kiro/skills/inception/SKILL.md` を読み、INCEPTIONワークフローを実行
2. ユーザーをガイド: ワークスペース検出 → 要件分析 → ストーリー → アーキテクチャ
3. 確定した技術スタックを「プロジェクト固有設定」セクションに記入
4. `gh issue create` でGitHub issueを生成
5. ユーザーに `./scripts/start-pipeline.sh` の実行を指示

設定が既に記入済みの場合はスキップ。

## プロジェクト固有設定

```
# フロントエンド: React + Vite (packages/web, packages/extension)
# バックエンド: Hono (packages/api)
# 共有: packages/shared
# パッケージマネージャ: pnpm (monorepo)
# Lint: oxlint .
# Typecheck: pnpm -r typecheck (tsc --build)
# Test: pnpm -r test (vitest)
# Build: pnpm -r build
# Dead code: knip
# Git: Conventional Commits
```

### 検証コマンド（コミット前に必ず実行）

```bash
# 全パッケージ共通
oxlint .
pnpm -r typecheck
pnpm -r test

# パッケージ単体（worktree内で対象パッケージのみ）
cd packages/<name> && npx oxlint . && npx tsc --noEmit && npx vitest run
```

## CI/CD ルール（GitHub Actions 必須）

### CI: PRごとに自動実行（必須）

PRを作成する前に、対象リポジトリに以下のCIワークフローが存在することを確認する。
存在しない場合は `.github/workflows/ci.yml` を作成してからPRを出すこと。

必須ジョブ:
1. **lint** — `oxlint .`
2. **typecheck** — `pnpm -r typecheck`
3. **test** — `pnpm -r test`
4. **build** — `pnpm -r build`

```yaml
# .github/workflows/ci.yml の最低要件
name: CI
on:
  pull_request:
    branches: [main]
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: pnpm/action-setup@v4
      - uses: actions/setup-node@v4
        with:
          node-version-file: '.node-version'
          cache: 'pnpm'
      - run: pnpm install --frozen-lockfile
      - run: oxlint .
      - run: pnpm -r typecheck
      - run: pnpm -r test
      - run: pnpm -r build
```

- **CI が全て通るまでマージ禁止** — branch protection rule で `ci` ジョブを required にする
- review エージェントは CI ステータスを `gh pr checks <number>` で確認してからマージ判断する
- CI 失敗した PR は implement エージェントが自分で修正する

### CD: IaC デプロイは CI/CD パイプラインに統合（必須）

手動デプロイ・ローカルからの `terraform apply` / `cdk deploy` は禁止。

| 環境 | トリガー | 方法 |
|------|---------|------|
| staging | PR マージ時 | GitHub Actions で自動デプロイ |
| production | リリースタグ or 手動承認 | GitHub Actions + environment protection |

ルール:
- `terraform plan` / `cdk diff` は PR の CI で自動実行し、結果を PR コメントに貼る
- `terraform apply` / `cdk deploy` は main マージ後の CD ワークフローでのみ実行
- エージェントがローカルで `apply` / `deploy` を実行してはならない
- IaC 変更がある PR には `infra` ラベルを付与し、plan 結果のレビューを必須にする
- シークレット（API キー、DB パスワード等）は GitHub Secrets / AWS Secrets Manager で管理。コードにハードコードしない

### GitLab プロジェクトの場合

GitHub Actions の代わりに `.gitlab-ci.yml` で同等のパイプラインを定義する:
- `lint`, `typecheck`, `test`, `build` の各ステージを定義
- MR (Merge Request) に対して自動実行
- IaC デプロイは `deploy` ステージで main マージ後に実行
- environment protection で production デプロイを制御

## 前提条件

- `git init` + `git remote add origin <url>` 設定済み
- `gh auth login` 認証済み
- これらがないと `gh issue list` 等が動作しない

## コード品質

- 問題を正しく解決する最小限のコード — YAGNI
- 賢さより読みやすさ
- 関数/モジュールごとに単一責任
- コードを書く前に要件を完全に理解する
- 既存のプロジェクト規約に従う

## アーキテクチャ

- **バックエンド**: Clean Architecture + DDD + Hexagonal — 詳細は `.kiro/skills/clean-ddd-hexagonal/SKILL.md`
- **フロントエンド**: Bulletproof React featureベースコロケーション — 詳細は `.kiro/skills/bulletproof-react/SKILL.md`
- featureごとにコード（コンポーネント、hooks、API、型、テスト）をコロケーション
- feature間の直接importは禁止（index.ts経由 or shared/に抽出）
- 新しいコードを追加する前に、該当スキルのディレクトリ構成とimportルールを確認すること

## 実装

- TDD: Red → Green → Refactor。テストなしのコード禁止
- 3層テスト必須: ユニット（関数単位）+ 統合（API単位）+ E2E（ユーザーフロー単位）
- エラー処理: サイレントcatch禁止、ユーザーに分かるメッセージ、リソースクリーンアップ
- API: フロントエンド↔バックエンドの型は常に同期、両端でバリデーション
- パフォーマンス: N+1禁止、ループ内API呼び出し禁止、不要な再レンダリング防止
- 詳細ガイドラインは `.kiro/skills/quality-guidelines/SKILL.md` を参照

## Git

- **全作業はgit worktreeで** — メインリポジトリでcheckout/switchしない
- ブランチ: `<type>/issue-<number>-<short-description>`
- コミット: Conventional Commits、英語、アトミック
- PR: 英語タイトル + 本文、`Closes #N`、squash mergeのみ
- CI通過前のマージ禁止。force merge禁止。
- **vim/nano等のエディタを起動するコマンドは禁止** — `git rebase`, `git commit` 等でエディタが開くとエージェントがハングする。必ず `--no-edit`, `-m` オプション等でエディタ起動を回避すること。`GIT_EDITOR=true` を設定するか、コマンドにメッセージを直接渡す。

### 禁止されたgit操作（絶対厳守）

| 禁止コマンド | 理由 | 代替 |
|-------------|------|------|
| `git push origin main` | mainへの直接pushは禁止 | PRを作成してマージ |
| `git push --force` | 他エージェントの作業を破壊する | `--force-with-lease` を使う |
| `git push -f` | 上記の短縮形 | `--force-with-lease` を使う |
| `git checkout main && git merge` | mainへの直接マージ禁止 | `gh pr merge --squash` |
| `git branch -D` | 他エージェントのブランチを削除する恐れ | PRマージ時の `--delete-branch` のみ |

### pre-commit（必須）

コミット前に必ず lint と test を実行すること。CI失敗を未然に防ぐ。

```bash
# コミット前に必ず実行
oxlint .
pnpm -r typecheck
pnpm -r test
```

- lint/test が通らないコードはコミットしない
- 「push してから CI で確認」は禁止 — ローカルで通してからpush
- CI失敗した場合は、そのPRの作成者（Implエージェント）が自分で修正する

## Issue作成ルール

### 作成上限（暴走防止）

| エージェント | 1サイクルあたりの上限 | 理由 |
|------------|---------------------|------|
| improve | 3件 | 改善issueの大量生成を防止 |
| e2e-bug-hunt | 5件 | バグissueの大量生成を防止 |
| watch-main | 3件 | マージ後検証のバグissue |
| implement | 0件 | issueを作らない（消化するのみ） |
| review | 0件 | issueを作らない |
| fix-review | 1件 | 再issue化のみ |

上限に達したらそのサイクルは終了し、次サイクルまで待つこと。

### issue/PRの勝手なclose禁止

| 禁止操作 | 例外 |
|---------|------|
| `gh issue close` | fix-reviewが再issue化する際の元issueのみ |
| `gh pr close` | fix-reviewが修正不能と判断したPRのみ（必ず再issue化とセット） |

理由なく issue/PR を close してはならない。close する場合は必ずコメントで理由を記載すること。

### 優先度ラベル（全issue必須）

| ラベル | 意味 | 例 |
|-------|------|-----|
| `P0-critical` | ユーザーをブロック or 本番障害 | セキュリティ脆弱性、データ損失 |
| `P1-high` | 重要だがブロックはしない | UXに影響するバグ、バリデーション欠如 |
| `P2-medium` | 早めに対応すべき | リファクタリング、パフォーマンス改善 |
| `P3-low` | あると嬉しい | ドキュメント、軽微なDX改善 |

`gh issue create` には必ず `--label "優先度" --label "<P0-critical|P1-high|P2-medium|P3-low>"` を含めること。Implエージェントは P0→P1→P2→P3 の順で取得する。

### コンフリクト防止

issue作成前に、既存のopen issueと変更対象ファイルの重複を確認:
```bash
gh issue list --state open --json number,title,body --jq '.[].body' | grep -i "<対象ファイルまたはモジュール>"
```

| 状況 | アクション |
|------|-----------|
| 既存issueと重複なし | 独立issueとして作成 |
| 既存issueと重複あり | 本文に `depends-on: #<番号>` を記載し `blocked` ラベルを付与 — 依存先がmergeされるまでImplは着手禁止 |

### 依存関係の本文フォーマット

```markdown
## 依存関係
- depends-on: #<番号>（先にmergeが必要）
```

## ファイルシステム制約（絶対厳守）

プロジェクトルート（`git rev-parse --show-toplevel` の結果）より上の階層への操作は一切禁止。

### 禁止コマンド例

- `cd ..` でプロジェクト外に移動
- `mkdir`/`touch`/`cp`/`mv`/`rm` 等でプロジェクト外のパスを指定
- `../` を含むパスへの書き込み・作成
- `/tmp` 等プロジェクト外への `git worktree add`（`rebase-prs` の一時worktreeを除く）

### 許可される操作

- プロジェクトルート配下のファイル読み書き
- `git worktree add .worktrees/<name>` （プロジェクト内worktree）
- `/tmp` への一時ファイル読み書き（ビルド成果物・ログ等の一時利用のみ）

違反した場合、そのコマンドの実行結果に関わらず作業を中断し、プロジェクト内で同等の操作をやり直すこと。

## セキュリティ

- シークレットのハードコード禁止。入力バリデーション。パラメータ化クエリ。最小権限の原則。

## 並列エージェント

- **排他制御の主体はGitHub issueのassignee** — assigneeがいるissueは他エージェントが作業中なので絶対に取らない
- issueを取る時は即座に `gh issue edit <number> --add-assignee @me` でロック
- `issue/task.md` は補助記録として併用 — 作業開始前に読み、更新する
- 他のエージェントが作業中のファイルは変更しない
- issue/PRコメントは全て英語

### stale worktree/ブランチの掃除

実装エージェントはサイクル開始時に以下を実行し、自分が残したゴミを掃除すること:

```bash
# マージ済みブランチに対応するworktreeを削除
git worktree list --porcelain | grep -B2 'prunable' | grep 'worktree' | awk '{print $2}' | xargs -I{} git worktree remove {}
# prunable worktreeを一括削除
git worktree prune
```

- PRがマージ済み or closeされたブランチのworktreeは削除する
- 他エージェントのworktreeは触らない（assigneeで判断）
- `git worktree remove` は自分が作成したworktreeのみ

## ユーザー確認事項の通知

ユーザーの判断が必要な場合（環境設定、シークレット、デプロイ承認、設計判断等）は `.agent-status/user-attention.json` に書き込む。Progress Report に赤文字で表示される。

```bash
# 追記する場合（既存の配列に追加）
jq --arg from "$AGENT_NAME" --arg msg "確認内容" \
  '. += [{from: $from, message: $msg, ts: (now | todate)}]' \
  .agent-status/user-attention.json > .agent-status/user-attention.json.tmp \
  && mv .agent-status/user-attention.json.tmp .agent-status/user-attention.json

# ファイルが存在しない場合は新規作成
echo '[{"from":"'$AGENT_NAME'","message":"確認内容","ts":"'$(date -u +%Y-%m-%dT%H:%M:%SZ)'"}]' > .agent-status/user-attention.json
```

- ユーザーが Operator 経由で対応したら、Operator が該当エントリを削除する
- 自分で解決できた場合は自分で該当エントリを削除する
- 溜め込みすぎない（最大10件）
