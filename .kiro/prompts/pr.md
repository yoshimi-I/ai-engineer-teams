
# PR作成

現在の変更からPRを作成してURL報告する。

## 手順

1. `git status`, `git diff --stat`, `git log` でDiff分析
2. エビデンス収集（テスト結果、lint結果等）
3. `git push -u origin $(git branch --show-current)`
4. `.github/PULL_REQUEST_TEMPLATE.md` を読み、テンプレートの全セクションを埋める
5. `BASE_BRANCH="${KIRO_INTEGRATION_BRANCH:-develop}"` を設定し、`gh pr create --base "$BASE_BRANCH" --title "..." --body "$(cat <作成したPR本文>)"` で作成する
6. `gh pr view --json baseRefName --jq '.baseRefName'` が `$BASE_BRANCH` と一致することを確認する。一致しなければ `gh pr edit --base "$BASE_BRANCH"` で修正する
7. PR URLをユーザーに提示

## PR本文テンプレート

`.github/PULL_REQUEST_TEMPLATE.md` が存在する場合は必ずそれに沿う。現行テンプレート:

```markdown
## Related Issue

closes #<issue-number>

## Changes

- <change summary>

## Checklist

- [x] Tests added/updated
- [x] Lint/format passed
- [x] No breaking changes (or documented)
```

チェック項目は実際に満たしたものだけ `[x]` にする。未実施の場合は `[ ]` のままにし、理由をPR本文に追記する。

## ルール

- mainブランチから直接PRは作らない
- 通常PRのbase branchは必ず `${KIRO_INTEGRATION_BRANCH:-develop}`。base未指定の `gh pr create` は禁止
- `${KIRO_STABLE_BRANCH:-main}` 向けPRは develop 昇格専用フローだけが作成する
- メインリポジトリで `git checkout` / `git switch` してPRブランチに移動しない。PR作成はissue専用worktree内で行う
- `--no-verify` や `--force` は使わない
- PRタイトルはConventional Commits形式
- PR本文は英語で書く
- `Related Issue` には必ず `closes #<issue-number>` を入れる
- レビューやマージは行わない — PR作成のみ
