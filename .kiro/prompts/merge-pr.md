
# PR作成→developマージ

現在の変更からPR作成→CI確認→`${KIRO_INTEGRATION_BRANCH:-develop}`へスカッシュマージまでを一気通貫で行う。`${KIRO_STABLE_BRANCH:-main}` へは E2E 通過後の昇格フローだけが取り込む。

## 手順

1. `git status`, `git diff` で変更確認
2. issue専用worktree内で作業していることを確認（メインリポジトリでcheckout/switchしない）
3. コミット（Conventional Commits形式）
4. `git push` → `.github/PULL_REQUEST_TEMPLATE.md` に沿った本文でPR作成:
   ```bash
   BASE_BRANCH="${KIRO_INTEGRATION_BRANCH:-develop}"
   gh pr create --base "$BASE_BRANCH" --title "<Conventional Commit title>" --body "$(cat <PR本文ファイル>)"
   ```
5. `gh pr checks --watch` でCI確認
6. CI全パス → `gh pr merge --squash --delete-branch`
7. PRの `baseRefName` が `${KIRO_INTEGRATION_BRANCH:-develop}` であることを確認する。違う場合はマージせず `gh pr edit --base "${KIRO_INTEGRATION_BRANCH:-develop}"` で修正する

## ルール

- CIが通らないコード変更をマージしない
- 通常PRのbase branchは必ず `${KIRO_INTEGRATION_BRANCH:-develop}`。`${KIRO_STABLE_BRANCH:-main}` へ直接出した通常PRはマージしない
- 1 PR = 1つの論理的な変更単位
- PRタイトルはConventional Commits形式
- PR本文は `.github/PULL_REQUEST_TEMPLATE.md` に沿って英語で書く
- `Related Issue` には必ず `closes #<issue-number>` を入れる
