
# PR監視・自動レビュー・マージ

open PRをポーリングし、未レビューPRを厳格レビュー → 全チェック通過時のみスカッシュマージ。

## CI通過の確認（最優先）

```bash
gh pr checks <number> --watch
```
- 全チェック通過 → マージしてよい
- それ以外 → **絶対にマージ禁止**

## 基本姿勢

**デフォルトは差し戻し。** マージは全チェックを通過した場合のみ。

## 1サイクルの処理

### Step 1: Open PR取得
```bash
gh pr list --json number,title,headRefName,statusCheckRollup
```

### Step 2: CI/CDステータス確認

| ステータス | アクション |
|-----------|-----------|
| CI全通過 + コンフリクトなし | レビューへ進む |
| CI失敗 | **絶対にマージ禁止** |
| コンフリクトあり | `/resolve-conflicts` プロンプトで解決 |
| CI未完了 | スキップ（次サイクルで再確認） |

### Step 3: 厳格レビュー
`/review` プロンプトの全フェーズを実行。省略禁止。

### Step 4: レビュー結果をPRにコメント
```bash
gh pr comment <number> --body "レビュー内容"
```

### Step 5: 結果に基づくアクション

| 条件 | アクション |
|------|-----------|
| 🔴 修正必須 | コメント投稿のみ（/fix-review エージェントが修正する） |
| 🟢 LGTM（検証証拠あり） | コメント投稿 → base branch が `${KIRO_INTEGRATION_BRANCH:-develop}` の場合のみ squash merge |
| 3回修正しても 🔴 が残る | 人間エスカレーション |

### Step 6: マージ実行
```bash
BASE_BRANCH=$(gh pr view <number> --json baseRefName --jq '.baseRefName')
if [ "$BASE_BRANCH" = "${KIRO_INTEGRATION_BRANCH:-develop}" ]; then
  gh pr merge <number> --squash --delete-branch
fi
```

マージ失敗（コンフリクト等）の場合:
```bash
gh pr comment <number> --body "🔴 マージ失敗: コンフリクトが発生しました。リベースが必要です。"
```
→ /fix-review エージェントがリベースして再push。次サイクルで再確認。

## 絶対禁止事項

- CI失敗中のPRをマージする
- diff だけ読んで LGTM
- force merge
- 検証証拠なしで approve
