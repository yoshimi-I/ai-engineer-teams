
# 自律実装

ユーザーの指示を待たず、即座にopen issueを自動取得して実装を開始する。調査→判断→実装→PR作成まで一気通貫で行う。issue番号の指定がなくても自分で選んで着手すること。

## 実装開始前の競合チェック（必須・省略禁止）

以下の3ステップを実装開始前に必ず実行すること。1つでもスキップしたら実装に入ってはならない。

### Step 0-1: assignee で着手状況を確認（排他制御）
```bash
gh issue view <issue番号> --json assignees --jq '.assignees[].login'
```
- **assigneeが既にいるissueは絶対に取らない**（他エージェントが着手中）
- assigneeが空のissueのみ対象
- issueを取る場合は**即座に**自分をアサインしてロックする:
  ```bash
  gh issue edit <issue番号> --add-assignee @me
  ```
- アサイン後に `issue/task.md` も更新する（補助記録）

### Step 0-2: 他の作業ブランチとworktreeを確認
```bash
git branch -a | grep -v "^*" | head -30
git worktree list
```
- 同じファイル群を触るブランチがあればスキップ
- **worktreeが存在する場合、別のKiroエージェントがそのブランチで作業中の可能性が高い。そのworktreeに対応するissueは絶対に取らない**

### Step 0-3: issueに既存PRがないか確認
```bash
gh issue view <issue番号>
gh pr list --search "head:<branch-name>"
```
- 既にPRが作成されているissueは取らない
- 「レビュー中」のPRがあるissueも取らない

**3ステップすべてクリアしてから実装に入る。**

## Worktree必須ルール（絶対厳守）

実装作業は必ずissue専用のgit worktreeで行う。メインリポジトリの作業ディレクトリでは、コード編集・テスト・コミットをしてはならない。

禁止:
- `git checkout -b <branch>` をメインリポジトリで実行する
- `git switch -c <branch>` をメインリポジトリで実行する
- メインリポジトリ上で直接ファイルを編集する
- `.worktrees/` 以外にworktreeを作る

必須手順:
```bash
ISSUE=<issue番号>
BRANCH="<type>/issue-${ISSUE}-<short-description>"
WORKTREE=".worktrees/issue-${ISSUE}-<short-description>"

BASE_BRANCH="${KIRO_INTEGRATION_BRANCH:-develop}"
git fetch origin "$BASE_BRANCH"
git worktree add -b "$BRANCH" "$WORKTREE" "origin/${BASE_BRANCH}"
cd "$WORKTREE"
```

以降の調査・実装・検証・コミット・push・PR作成は、すべて `cd "$WORKTREE"` 後のworktree内で実行する。

PR作成:
```bash
git push -u origin "$BRANCH"
cat > /tmp/pr-body-${ISSUE}.md <<EOF
## Related Issue

closes #${ISSUE}

## Changes

- <change summary>

## Checklist

- [x] Tests added/updated
- [x] Lint/format passed
- [x] No breaking changes (or documented)
EOF
gh pr create --base "$BASE_BRANCH" --title "<Conventional Commit title>" --body "$(cat /tmp/pr-body-${ISSUE}.md)"
```

`.github/PULL_REQUEST_TEMPLATE.md` が存在する場合は、必ずそのセクション構成に沿ってPR本文を作成する。チェック項目は実際に満たしたものだけ `[x]` にする。

PR作成後、CIの結果を確認する:
```bash
sleep 30
gh pr checks <PR番号> --watch --fail-fast 2>/dev/null || true
gh pr checks <PR番号>
```
- CI全通過 → task.md更新して次のissueへ
- CI失敗 → 失敗ログを確認し自分で修正してpush。最大3回まで再試行。

PR作成後もworktreeはPRがmergeされるまで残す。勝手に削除しない。

## Issue進捗管理（必須・省略禁止）

**排他制御の主体はGitHub issueのassignee。** task.mdは補助記録。

### assignee（排他制御 — 最優先）

| タイミング | 操作 |
|-----------|------|
| issue選択直後 | `gh issue edit <number> --add-assignee @me` |
| PR作成後 | assigneeはそのまま維持 |
| マージ後 | Reviewエージェントがissueをclose |

- assigneeがいるissue = 誰かが作業中 → **絶対に取らない**
- これがエージェント間の排他制御の唯一の信頼できるソース

### task.md（補助記録）

`issue/task.md` はローカルの進捗記録として併用する。

- 実装開始前に必ず `issue/task.md` を読む
- 実装開始時に必ず `着手中` で追記してから作業を始める
- PR作成後に必ず `レビュー中` に更新する
- task.md のヘッダー行（テーブル定義 + 記入例）は絶対に削除しない

ファイルが存在しない場合は以下のテンプレートで新規作成すること:

```markdown
# Issue Tracker
<!-- ⚠️ このヘッダーと記入例の行は削除禁止 -->

| Issue | タイトル | ステータス | ブランチ |
|-------|---------|-----------|---------| 
| #999 | （記入例）feat: 〇〇機能追加 | 着手中 / レビュー中 / merge済み / 解決済み（変更不要） | feat/issue-999-xxx |
```

### ステータスの種類と意味

| ステータス | 意味 | 遷移タイミング |
|-----------|------|---------------|
| `着手中` | 実装作業中 | issue選択直後、実装開始前 |
| `レビュー中` | PR作成済み、マージ待ち | `git push` + `gh pr create` 完了後 |
| `merge済み` | mainにマージ完了 | PRがマージされた後 |
| `解決済み（変更不要）` | 調査の結果、既に修正済み | コード確認で問題なしと判断した場合 |
| `解決済み（実装済み）` | 既存コードで要件を満たしている | 既にモジュール等が存在していた場合 |

## Issue自動選択ルール

issue番号の指定がない場合:

1. open issueを取得し、assigneeが空のものだけを候補にする:
   ```bash
   gh issue list --state open --json number,title,labels,assignees --jq '[.[] | select(.assignees | length == 0)]'
   ```
2. 候補の中から優先順位に従い1つ選ぶ
3. 着手中issueとのコンフリクト判定
4. 問題なければ **即座に** `gh issue edit <number> --add-assignee @me` → task.md更新 → 実装開始

### コンフリクト判定

| コンフリクトの程度 | 判定 | 例 |
|-------------------|------|-----|
| なし | OK | 完全に別領域（backend vs frontend等） |
| 軽微 | OK | 同一ファイルだが変更箇所が離れている |
| 中程度〜大 | スキップ | 同一関数・同一コンポーネントを変更する |

### 優先順位

1. `P0-critical` ラベル
2. `P1-high` ラベル
3. `P2-medium` ラベル
4. `P3-low` ラベル
5. ラベルなし（最後）

- `blocked` ラベルのissueは依存先がmergeされるまでスキップ
- 同一優先度内ではissue番号が小さい（古い）ものを優先

## Process — 永久ループ

**このプロンプトは無限ループで動作する。openなissueが0になるまで絶対に停止しない。**

```
┌─→ 1. Issue選択
│   2. 調査
│   3. 実装
│   4. 検証 & PR
│   5. task.md更新
└── 6. 即座にステップ1へ戻る ← ここで停止・待機・質問しない
```

### 各ステップ詳細

1. **Issue選択**:
   - `issue/task.md` を読み、着手中・レビュー中を把握
   - `gh issue list --state open` で未着手issueを取得
   - 上記「Issue自動選択ルール」に従い1つ選択
   - **openなissueが0件 → ループ終了を宣言して停止**
   - 番号指定時は初回のみそのissueを実装し、完了後は自動選択に切り替え

2. **調査**: 関連ファイルを最低3つ読む（変更対象+呼び出し元+型定義）

3. **実装**: issue専用worktreeを作成し、そのworktree内で下記「領域別の実装ガイド」に従って実装

4. **検証**: 領域に応じたlint・テストコマンドを実行（steering参照）

5. **コミット&PR**: Conventional Commits形式でコミット、`gh pr create` でPR作成、task.mdを`レビュー中`に更新

6. **次のissueへ**: 完了報告と同時にステップ1へ戻る。**ユーザーへの確認・待機は禁止**

### ループ停止条件（これ以外では停止しない）

| 条件 | 動作 |
|------|------|
| openなissueが0件 | 「全issueを処理しました」と報告して停止 |
| ユーザーが明示的に「止めて」「停止」と言った | 即座に停止 |
| 致命的エラー（git操作不能、API到達不能等） | エラー報告して停止 |

### 絶対にやってはいけないこと

| 禁止行為 | 理由 |
|---------|------|
| 「次のissueに進みますか？」と聞く | ループなので聞かない |
| 1つ完了して報告だけして待機 | 即座に次へ進む |
| 「他に何かありますか？」 | issueがある限り自分で取る |
| issue一覧を見せて選ばせる | 自分で優先度判定して選ぶ |

## 利用するスキル

実装の各フェーズで、該当するスキルのSKILL.mdを `fs_read` で読んで参照すること。

| フェーズ | スキル | 条件 |
|---------|--------|------|
| フロントエンド実装 | `frontend-design` | UI/コンポーネントの変更がある場合 |
| UI品質チェック | `baseline-ui` | Tailwind CSSでUIコンポーネントを実装する場合 |
| アクセシビリティ | `fixing-accessibility` | インタラクティブ要素、フォーム、ダイアログの追加・変更時 |
| メタデータ | `fixing-metadata` | 新規ページ追加、SEO・OGP対応が必要な場合 |
| アニメーション | `fixing-motion-performance` | アニメーション・トランジションの追加・変更時 |
| バックエンド設計 | `clean-ddd-hexagonal` | ドメインモデル・API設計の変更がある場合 |
| IaC (Terraform) | `terraform-style-guide` | Terraformファイルの追加・変更がある場合 |
| IaC (CDK) | `aws-cdk-development` | AWS CDKスタックの追加・変更がある場合 |
| CI/CD | `ci-cd-pipeline-patterns` | ワークフロー・パイプラインの追加・変更がある場合 |
| DBスキーマ変更 | `database-migration` | テーブル・カラム・インデックスの追加・変更・削除がある場合 |
| モニタリング | `monitoring-observability` | メトリクス・アラート・ログ設定の追加・変更がある場合 |
| モバイル (RN) | `react-native-best-practices` | React Nativeコンポーネントの追加・変更がある場合 |
| データパイプライン | `etl-pipeline` | ETL/データ変換処理の追加・変更がある場合 |

## 領域別の実装ガイド

### フロントエンド変更がある場合

1. `frontend-design` スキルを読み、デザイン品質を担保する
2. `baseline-ui` スキルでアンチパターンをチェック
3. `fixing-accessibility` スキルでアクセシビリティを確認
4. 新規ページの場合は `fixing-metadata` スキルでメタデータを設定
5. アニメーション追加時は `fixing-motion-performance` スキルでパフォーマンスを確認
6. 既存コンポーネントのパターンを確認
7. steering ファイルからフロントエンドの検証コマンドを確認して実行

### バックエンド変更がある場合

1. `clean-ddd-hexagonal` スキルの原則に沿っているか確認
2. 既存のAPI・モデル・サービスのパターンを確認
3. steering ファイルからバックエンドの検証コマンドを確認して実行
4. API変更がある場合はリクエスト/レスポンスの型定義も更新

### フルスタック変更がある場合

1. バックエンドのAPI変更 → フロントエンドの型定義・API呼び出しも更新
2. 両方の検証コマンドを実行
3. フロントエンド↔バックエンドの整合性を確認

### インフラ変更がある場合

1. Terraform → `terraform-style-guide` スキルを読み、命名・構造規約に従う
2. CDK → `aws-cdk-development` スキルを読み、パターンに従う
3. `terraform plan` または `cdk diff` で差分を確認
4. 既存リソースへの影響範囲を把握
5. 破壊的変更がないか確認
6. CI/CDパイプライン変更がある場合は `ci-cd-pipeline-patterns` スキルを参照

### DBスキーマ変更がある場合

1. `database-migration` スキルを読み、安全なマイグレーションパターンに従う
2. 後方互換性を確認（新コードが旧スキーマでも動くか）
3. ロールバック可能か確認
4. NOT NULL追加 → デフォルト値は？既存行は？

### モバイル (React Native) 変更がある場合

1. `react-native-best-practices` スキルを読む
2. パフォーマンス（FlatList/FlashList、再レンダリング、メモリリーク）を確認
3. プラットフォーム固有の問題（iOS/Android差異）を確認

### データパイプライン変更がある場合

1. `etl-pipeline` スキルを読む
2. データ品質チェック（スキーマ検証、null処理、重複排除）を確認
3. 冪等性を確認（再実行しても結果が同じか）

## ループ継続の強制ルール

- PR作成完了後、**同じレスポンス内で**次のissue選択を開始すること
- エラーが発生しても、そのissueをスキップして次のissueに進む（致命的エラー以外）
- 「完了しました」で文章を終えない。必ず「次のissueに着手します」で続ける
- ユーザーからの返答を待たない。自分のターンで可能な限り多くのissueを処理する

## Common Mistakes

- **task.md 未更新で実装開始** → 他エージェントと重複作業の原因
- **task.md のヘッダー行を削除** → テンプレートが崩れる
- 調査せずに実装 → 最低3ファイルは読む
- フロントエンド実装でスキルを無視 → デザイン品質が低下
- バックエンド実装でレイヤー分離を無視 → 保守性が低下
- フルスタック変更でフロント↔バックの型不整合 → ランタイムエラーの原因
