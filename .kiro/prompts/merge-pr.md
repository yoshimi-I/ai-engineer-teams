
# PR作成→mainマージ

現在の変更からPR作成→CI確認→mainへスカッシュマージまでを一気通貫で行う。

## 手順

1. `git status`, `git diff` で変更確認
2. issue専用worktree内で作業していることを確認（メインリポジトリでcheckout/switchしない）
3. コミット（Conventional Commits形式）
4. `git push` → `.github/PULL_REQUEST_TEMPLATE.md` に沿った本文で `gh pr create`
5. `gh pr checks --watch` でCI確認
6. CI全パス → `gh pr merge --squash --delete-branch`
7. ローカルmainを最新に同期

## ルール

- CIが通らないコード変更をマージしない
- 1 PR = 1つの論理的な変更単位
- PRタイトルはConventional Commits形式
- PR本文は `.github/PULL_REQUEST_TEMPLATE.md` に沿って英語で書く
- `Related Issue` には必ず `closes #<issue-number>` を入れる
