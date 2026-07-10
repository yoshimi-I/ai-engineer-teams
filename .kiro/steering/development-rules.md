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

以下の「プロジェクト固有設定」セクションが未確定 (コメントまたは "TBD" のみ) の場合:
1. `.kiro/skills/inception/SKILL.md` を読み、INCEPTION ワークフローを実行
2. ワークスペース検出で既存コード・ツール・CI を把握
3. 要件、制約、チームの好みをすり合わせ、技術スタックを決定
4. 合意した技術スタック・ディレクトリ構成・検証コマンドを「プロジェクト固有設定」セクションに記入
5. `gh issue create` で GitHub issue を生成
6. ユーザーに `./scripts/start-pipeline.sh` の実行を指示

設定が既に記入済みでも、既存コードと矛盾する場合は INCEPTION で見直す。

## プロジェクト固有設定

<!--
このテンプレートは意図的に空です。INCEPTION ワークフローがプロジェクトに
合わせて埋めます。プロジェクトが Node/pnpm/Python/Go/Rust/Bash いずれでも
動くよう、特定スタックを前提としないでください。
-->

```
# 言語 / フレームワーク: Bash scripts + GitHub CLI + zellij orchestration
# パッケージマネージャ: なし（macOS は Homebrew、Ubuntu CI は apt で shellcheck/bats を導入）
# Lint コマンド: shellcheck -x -P scripts scripts/*.sh scripts/lib/*.sh scripts/tests/*.bash scripts/tests/*.bats
# Typecheck コマンド: なし（Bash プロジェクト）
# Test コマンド: ./scripts/check.sh
# Build コマンド: なし（スクリプト配布）
# Dead code 検出: なし（任意）
# Git: Conventional Commits
```

### 検証コマンド (コミット前に必ず実行)

プロジェクト固有設定に書かれた Lint / Typecheck / Test コマンドをコミット前に実行する。
未確定の場合は INCEPTION を先に終わらせること。

```bash
./scripts/check.sh
```

CI で実行されるチェックは必ずローカルでも通してから push する。CI 失敗 PR は implement エージェントが自身で修正する。

## CI/CD ルール

### CI: PR ごとに自動実行 (必須)

PR を作成する前に、対象リポジトリに CI ワークフローが存在することを確認する。
存在しない場合は、プロジェクトのスタックに合わせて `.github/workflows/ci.yml` を作成してから PR を出す。

必須ジョブ (プロジェクト固有設定に従って具体化):

| ジョブ | 目的 | 実装例 |
|--------|------|--------|
| **lint** | 構文・スタイル | `eslint`, `oxlint`, `ruff`, `golangci-lint`, `shellcheck` 等 |
| **typecheck** | 型検証 | `tsc`, `mypy`, `pyright` 等 (型言語のみ) |
| **test** | ユニット/統合テスト | `vitest`, `jest`, `pytest`, `go test`, `cargo test`, `bats` 等 |
| **build** | ビルド成功確認 | `tsc --build`, `vite build`, `cargo build`, `go build` 等 |

ワークフローの最小例 (プロジェクトのスタックに合わせて置換する):

```yaml
name: CI
on:
  pull_request:
    branches: [develop]
jobs:
  ci:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      # 以下はプロジェクトのスタックに合わせて書き換える
      # Node + pnpm の例:
      #   - uses: pnpm/action-setup@v4
      #   - uses: actions/setup-node@v4
      #     with: {node-version-file: .node-version, cache: pnpm}
      #   - run: pnpm install --frozen-lockfile
      #   - run: pnpm -r lint typecheck test build
      # Python + uv の例:
      #   - uses: astral-sh/setup-uv@v4
      #   - run: uv sync && uv run ruff check && uv run pytest
      # Bash のみの例 (このリポジトリ自身):
      #   - run: sudo apt-get install -y shellcheck bats
      #   - run: ./scripts/check.sh
```

- **CI が全て通るまでマージ禁止** — branch protection rule で CI ジョブを required にする
- review エージェントは CI ステータスを `gh pr checks <number>` で確認してからマージ判断
- CI 失敗 PR は implement エージェントが自身で修正する

### CD: IaC デプロイは CI/CD パイプラインに統合 (必須)

IaC (Terraform / CDK / Pulumi 等) を使うプロジェクトのみ適用。

手動デプロイ・ローカルからの `terraform apply` / `cdk deploy` / `pulumi up` は禁止。

| 環境 | トリガー | 方法 |
|------|---------|------|
| staging | PR マージ時 | GitHub Actions で自動デプロイ |
| production | リリースタグ or 手動承認 | GitHub Actions + environment protection |

ルール:
- `terraform plan` / `cdk diff` / `pulumi preview` は PR の CI で自動実行し、結果を PR コメントに貼る
- `terraform apply` / `cdk deploy` / `pulumi up` は main 昇格後の CD ワークフローでのみ実行
- エージェントがローカルで `apply` / `deploy` を実行してはならない
- IaC 変更がある PR には `infra` ラベルを付与し、plan 結果のレビューを必須にする
- シークレットは GitHub Secrets / クラウド Secret Manager で管理。コードにハードコードしない

### GitLab プロジェクトの場合

GitHub Actions の代わりに `.gitlab-ci.yml` で同等のパイプラインを定義:
- lint / typecheck / test / build の各ステージ
- MR に対して自動実行
- IaC デプロイは `deploy` ステージで main 昇格後に実行
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
| `git push origin develop` | developへの直接pushは禁止 | PRを作成してマージ |
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

詳細は `.kiro/skills/inception/references/issue-generation.md` 参照。

### コア原則

- **小さく、多くて構わない**: 1 issue = 1 PR = 15 分で読めるレビュー。
  数を減らすために粗く切るより、小粒で並列化しやすく切る方が常に速い。
- **Walking Skeleton を最初に通す**: 機能を横に広げる前に、最小 E2E 貫通路を
  1 本完成させる (scaffold + CI + 1 機能 + E2E + deploy)。
- **垂直スライスを優先**: 機能は DB → API → UI → テストで縦に薄く割る。
  水平レイヤー分割は scaffold / 共通型 / CI / IaC などの土台のみ。
- **依存タイプを明記**: `blocked-by: #N (contract|data|impl|infra|test)`

### 粒度の目安 (超えそうなら分割)

| 項目 | 目安 |
|------|------|
| 正味 LOC | 50〜300 行 (テスト除く) |
| 触るファイル | 1〜5 |
| 受け入れ基準 | 1〜3 項目 |
| レビュー時間 | 5〜15 分 |
| テスト追加 | ユニット + 統合 or E2E の組 |

### 依存タイプ

| タイプ | 意味 | 例 |
|-------|------|-----|
| `contract` | 相手が型 / API / DB スキーマを公開するのを待つ | API 実装は contract issue 待ち |
| `data` | 相手が migration / seed を流すのを待つ | API は schema migration 待ち |
| `impl` | 相手の実装が動く状態を待つ (一番強い) | UI は API の動作確認済み待ち |
| `infra` | 相手が CI / CD / IaC / シークレットを用意するのを待つ | deploy は IaC 完成待ち |
| `test` | 相手の E2E 通過を待つ (リリース最終関門) | promote は E2E 通過待ち |

本文に必ず書く:
```markdown
## 依存関係
- blocked-by: #<番号> (<contract|data|impl|infra|test>)
- blocks: #<番号> (任意)
```

同じ issue 番号でも依存タイプが違えば扱いが違う。タイプが書かれていれば
AI planner が「contract だけ merge されれば並列に実装を始められる」と判断できる。

### 作成上限（暴走防止）

| エージェント | 1サイクルあたりの上限 | 理由 |
|------------|---------------------|------|
| improve | 3件 | 改善issueの大量生成を防止 |
| e2e-bug-hunt | 5件 | バグissueの大量生成を防止 |
| watch-main | 3件 | マージ後検証のバグissue |
| ui-audit | 3件 | デザイン改善issueの大量生成を防止 |
| implement | 0件 | issueを作らない（消化するのみ） |
| review | 0件 | issueを作らない |
| fix-review | 1件 | 再issue化のみ |

上限に達したらそのサイクルは終了し、次サイクルまで待つこと。

**INCEPTION と手動 create-issue には上限が無い**。小粒化のために issue 数が
40〜60 になっても構わない。粗くまとめる方がコストが大きい。

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

### Phase / Type ラベル (推奨)

| ラベル | 用途 |
|-------|------|
| `phase-0-foundations` | scaffold / CI / IaC |
| `phase-1-skeleton` | walking skeleton |
| `phase-2-feature` | 機能実装 |
| `phase-3-hardening` | error states / empty states / polish |
| `phase-4-release` | production 向け |
| `type-contract` | 型 / API / DB スキーマのみ |
| `type-data` | migration / seed |
| `type-impl` | 通常の実装 |
| `type-infra` | CI / CD / IaC |
| `type-test` | E2E / 追加テスト |
| `blocked` | 依存待ち (依存先 merge で自動解除) |
| `tracker` | 親 issue (Impl は着手しない) |

### デザイン品質

- UI変更PRは `Design Evidence` を必須とする
- desktop/mobile スクリーンショット、または合理的な代替検証をPR本文に記載する
- チープなUI、既存デザインから浮いたUI、状態不足、レスポンシブ崩れはレビューで修正必須
- `ui-audit` は `design-review` label と優先度 label を付けて issue を作成する

### コンフリクト防止

issue作成前に、既存のopen issueと変更対象ファイルの重複を確認:
```bash
gh issue list --state open --json number,title,body --jq '.[].body' | grep -i "<対象ファイルまたはモジュール>"
```

| 状況 | アクション |
|------|-----------|
| 既存issueと重複なし | 独立issueとして作成 |
| 既存issueと重複あり | 本文に `blocked-by: #<番号> (<type>)` を記載し `blocked` ラベルを付与 — 依存先がmergeされるまでImplは着手禁止 |

### 本文テンプレ (必須)

```markdown
## 概要
<1〜3 行でこの issue が何を足すか>

## 背景・動機
<なぜ必要か、どの要件/ストーリーを満たすか>

## スコープ
- ✅ 含む: <具体的にやること>
- ❌ 含まない: <別issueで扱うもの、触らないファイル>

## 変更対象
- <ファイルパス / ディレクトリ>

## 受け入れ基準
- [ ] <テスト可能な条件 1>
- [ ] <テスト可能な条件 2>
- [ ] 関連テスト追加 (ユニット / 統合 / E2E)

## 依存関係
- blocked-by: #<番号> (<contract|data|impl|infra|test>)

## 実装メモ
<関連アーキ決定、主な関数シグネチャ、気をつける点>
```

### アンチパターン

- ❌ `feat: implement authentication` (粗すぎ、5〜10 issue に割る)
- ❌ `feat: frontend + backend for login` (垂直混在、レイヤー別に割る)
- ❌ 並列化できないほど細かい `feat: rename variable foo to bar` (こちらは逆に統合)
- ❌ 依存タイプを書かず `depends-on: #5` だけ (contract/impl が見分けられない)
- ❌ Walking Skeleton を飛ばして機能実装に突入 (デリバリー不能)
- ❌ scaffold を 1 つの巨大 issue にまとめる (並列化機会を潰す)
- ❌ E2E をリリース直前に 1 issue で全部足す (実装と並行して厚くする)

### 依存関係の本文フォーマット (旧記法互換)

`depends-on: #<番号>` は後方互換で引き続き有効。新規 issue では
`blocked-by: #<番号> (<type>)` を推奨する。

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
