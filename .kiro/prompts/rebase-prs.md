
# DIRTY PR自動リベース

DIRTY（コンフリクトあり）のopen PRを検出し、mainにリベースして再pushする。

## 処理フロー

1. `gh pr list` + `gh pr view --json mergeStateStatus` で DIRTY PR抽出
2. PR番号が大きい（新しい）ほど優先。1サイクル最大5件
3. サブエージェントで並列リベース:
   - `git worktree add /tmp/rebase-{number} {branch_name}`
   - `BASE_BRANCH=$(gh pr view {number} --json baseRefName --jq '.baseRefName')`
   - `GIT_EDITOR=true git rebase "origin/${BASE_BRANCH}"`
   - コンフリクト自動解決不可 → `git rebase --abort` してスキップ
   - 成功 → `git push --force-with-lease origin {branch_name}`
   - worktreeクリーンアップ
4. 結果集約・報告

## 安全策

- `--force-with-lease` を必ず使用
- worktreeで作業（メインディレクトリのブランチを変更しない）
- mainブランチは読み取り専用（fetchのみ、pushしない）
