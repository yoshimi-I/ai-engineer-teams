
# レビュー指摘の自動修正ループ

ユーザーの指示を待たず、即座にレビュー指摘のあるPRを自動検出して修正を開始する。PRのレビューコメント（🔴 修正必須）を自動取得し、指摘を1つずつ修正→push→再レビュー待ちを繰り返す。

## OrchestratorからPR番号を割り当てられた場合

プロンプト末尾の `## Orchestrator assignment` に `GitHub PR #<number>` が含まれる場合は、そのPRだけを処理する。

- 対象PRが既にclosed/mergedなら終了する
- 対象PRが `CHANGES_REQUESTED` でなくなっているなら終了する
- 対象PRが自分以外のassigneeでロックされているなら終了する
- 他のPRを自動選択しない

## 1サイクルの処理

### Step 1: 修正が必要なPRを検出（多層検出）

以下の3層で検出し、いずれか1つでも該当すれば修正対象とする。

#### 層1: reviewDecision（最も信頼性が高い）
```bash
gh pr list --json number,title,headRefName,reviewDecision --limit 20
```
`reviewDecision` が `CHANGES_REQUESTED` のPRを対象にする。

#### 層2: 最新レビューのstate
`reviewDecision` が空や `REVIEW_REQUIRED` の場合でも、個別レビューに REQUEST_CHANGES がある場合がある:
```bash
gh pr view <number> --json reviews --jq '.reviews[-1].state'
```
最新レビューの state が `CHANGES_REQUESTED` なら対象。

#### 層3: コメント・レビュー本文のテキストマッチ
```bash
gh pr view <number> --json reviews,comments
```
「🔴 修正必須」または「🔴 マージ失敗」を含むレビュー/コメントがあれば対象。

**重要**: 3層のいずれかで検出されれば修正対象とする。reviews と comments の両方を必ず確認すること。

対象がなければ、APPROVEDでマージ待ちのPRを処理（後述）して終了。

### Step 1.5: PRのロック（排他制御）

対象PRを見つけたら、着手前にassigneeでロックする:
```bash
# 自分以外のassigneeがいたらスキップ（他のFix-Reviewが作業中）
ME=$(gh api user --jq '.login')
ASSIGNEE=$(gh pr view <number> --json assignees --jq '.assignees[].login' 2>/dev/null)
if [[ -n "$ASSIGNEE" ]] && ! echo "$ASSIGNEE" | grep -qx "$ME"; then
  echo "PR #<number> は $ASSIGNEE が作業中。スキップ。"
  # 次の対象PRを探す
fi

# assigneeが空、または自分がassigneeならこのPRを処理する
if [[ -z "$ASSIGNEE" ]]; then
  gh pr edit <number> --add-assignee @me
fi
```

重要:
- assigneeが自分（`gh api user --jq '.login'`）の場合は、過去サイクルのロック継続または自分の作業なのでスキップしない
- assigneeが自分以外の場合のみスキップする
- 対象PRが全て自分以外にロックされている場合は、何もせず終了する

修正完了後（merge or 次サイクルへ移行時）にassigneeを外す:
```bash
gh pr edit <number> --remove-assignee @me
```

### Step 2: 指摘内容の取得と理解

#### コンフリクト（🔴 マージ失敗）の場合
1. `git fetch origin` → `GIT_EDITOR=true git rebase origin/main`
2. コンフリクトを解決（`/resolve-conflicts` の手順に従う）
3. `git push --force-with-lease origin $(git branch --show-current)`
4. 即座にマージを試みる:
   ```bash
   gh pr merge <number> --squash --delete-branch
   ```
   マージ失敗時はPRにコメント: 「🔴 マージ失敗: リベース後もマージできません。」
5. 以降のStepはスキップ

#### レビュー指摘（🔴 修正必須）の場合
1. レビューコメントから指摘事項を抽出（ファイル、行、カテゴリ、修正案）
2. 指摘されたファイルと行を実際に読む
3. 修正案が正しいか検証

### Step 3: 指摘の分類 — 修正 or 反論

各指摘を技術的に検証し、以下の3つに分類する:

| 分類 | 判断基準 | アクション |
|------|---------|-----------|
| ✅ 正しい指摘 | 実際にバグ・問題がある | 修正する（Step 4へ） |
| ❌ 技術的に不正確な指摘 | 公式ドキュメント・仕様と矛盾する | 反論する（Step 3-Rへ） |
| ⚠️ 過剰な指摘 | 問題はないが「念のため」の変更要求 | 反論する（Step 3-Rへ） |

**重要**: 修正案を鵜呑みにしない。指摘が間違っている場合は修正せず反論する。

#### Step 3-R: 技術的反論の実施

指摘が不正確または過剰と判断した場合、PRにコメントで技術的根拠を示して反論する:

```bash
gh pr comment <number> --body "## 指摘への回答

### {指摘タイトル} — 対応不要と判断

**理由:**
{技術的根拠を具体的に説明。公式ドキュメント・仕様・実際の挙動を引用}

**検証:**
{実際にコードを読んで確認した結果}

**結論:**
この指摘については修正不要と判断しました。正しい指摘については修正済みです。再レビューをお願いします。"
```

反論後、正しい指摘の修正があればpushし、`gh pr review` でAPPROVEを要求する。

### Step 4: 正しい指摘の修正
1. 対象ブランチ用のworktreeを `.worktrees/fix-review-<PR番号>` に作成し、その中で作業する
2. 正しいと判断した指摘のみ修正する
3. 不正確な指摘に対する修正は行わない

```bash
BRANCH=$(gh pr view <number> --json headRefName --jq '.headRefName')
git fetch origin "$BRANCH"
git worktree add ".worktrees/fix-review-<number>" "$BRANCH"
cd ".worktrees/fix-review-<number>"
```

### Step 4: 検証
steering ファイルからプロジェクトの検証コマンドを確認し、実行する。
1つでも失敗したら修正をやり直す。

### Step 5: コミット & Push
```bash
git add -A
git commit -m "fix: レビュー指摘を修正"
git push origin $(git branch --show-current)
```

### Step 5.5: CI確認（必須 — push後に必ず実行）

push後、CIの結果を確認する。CIが通るまでこのPRの作業は完了しない。

```bash
# CI完了を待つ（最大5分）
sleep 30
gh pr checks <number> --watch --fail-fast 2>/dev/null || true
gh pr checks <number>
```

- **CI全通過** → Step 6へ進む
- **CI失敗** → 失敗したジョブのログを確認し、自分で修正する:
  ```bash
  gh run view <run-id> --log-failed
  ```
  修正後、再度 `git push` → CI確認を繰り返す。最大3回まで。
- **3回修正してもCI通らない** → PRにコメントして次のPRへ進む:
  ```bash
  gh pr comment <number> --body "⚠️ CI修正を3回試みましたが解決できません。手動確認が必要です。"
  ```

### Step 6: PRにコメント
```bash
gh pr comment <number> --body "レビュー指摘を修正しました。再レビューをお願いします。"
```

### Step 7: 再レビュー結果を確認し、APPROVEならマージ
修正push後、再レビューの結果を確認する。
```bash
gh pr view <number> --json reviewDecision --jq '.reviewDecision'
```
- `APPROVED` → 即座にマージ:
  ```bash
  gh pr merge <number> --squash --delete-branch
  ```
  マージ失敗時はPRにコメント:
  ```bash
  gh pr comment <number> --body "🔴 マージ失敗: コンフリクトが発生。リベースが必要です。"
  ```
- `CHANGES_REQUESTED` → Step 2 に戻って再修正
- まだレビューされていない → 次のPRへ進む（次サイクルで再確認）

## ループ停止条件

| 条件 | 動作 |
|------|------|
| 修正必要PRが0件 | APPROVEDでマージ待ちのPRを探してマージ（後述）→ 終了 |
| ユーザーが「止めて」と言った | 即座に停止 |
| 同じPRで2回修正+反論しても🔴が残る | 強制マージ判定（後述） |

## 同じPRで2回修正しても解決しない場合: 最終判定

レビューエージェントと修正エージェントの間で合意に至らない場合、以下の基準で判断する。

### 強制マージの条件（全て満たす場合のみ）
1. 正しい指摘は全て修正済み
2. 残っている指摘は技術的に反論済み（根拠をPRコメントに記載済み）
3. lint / 型チェック / テスト / ビルドが全て通過

上記を全て満たす場合:
```bash
gh pr comment <number> --body "## 強制マージ判定

正しい指摘は全て修正済みです。残りの指摘については技術的根拠を示して反論済みです。
全検証（lint/型チェック/テスト/ビルド）通過を確認したため、マージします。"
gh pr review <number> --approve --body "修正完了・検証通過・未解決指摘は反論済み"
gh pr merge <number> --squash --delete-branch
```

### 条件を満たさない場合: PRをcloseして再issue化

検証が通らない、または正しい指摘を修正しきれない場合は、PRをcloseして新しいissueを作成する:

```bash
# PRの情報を取得
TITLE=$(gh pr view <number> --json title --jq '.title')
BODY=$(gh pr view <number> --json body --jq '.body')
BRANCH=$(gh pr view <number> --json headRefName --jq '.headRefName')

# PRをclose
gh pr close <number> --comment "## PRクローズ

2回の修正サイクルで解決できなかったため、PRをクローズします。
未解決の問題を整理した新しいissueを作成します。"

# 新しいissueを作成（未解決の指摘と経緯を含める）
gh issue create \
  --title "再実装: ${TITLE}" \
  --body "## 経緯
PR #<number> で実装を試みたが、以下の問題が解決できずクローズ。

## 未解決の問題
{解決できなかった指摘を具体的に列挙}

## 前回の実装で正しかった部分
{維持すべきアプローチがあれば記載}

## 参考
- クローズしたPR: #<number>
- ブランチ: ${BRANCH}" \
  --label "bug"
```

## 修正対象がない場合: マージ待ちPRの処理

修正が必要なPRが0件の場合、APPROVEDでまだマージされていないPRを探して積極的にマージする。

```bash
gh pr list --json number,title,headRefName,reviewDecision --limit 20
```

`reviewDecision` が `APPROVED` のPRがあれば:
```bash
gh pr merge <number> --squash --delete-branch
```

マージ失敗時はコメントしてリベース対応:
```bash
gh pr comment <number> --body "🔴 マージ失敗: コンフリクトが発生。リベースが必要です。"
```

## ルール

- 修正案を鵜呑みにしない
- 技術的に不正確な指摘には根拠を示して反論する
- 指摘と無関係な変更を混ぜない
- 検証が通らない修正は push しない
- 他のエージェントが着手中のPRは触らない（task.md確認）
- 反論なしに指摘を無視してはいけない（必ずPRコメントで理由を説明する）
