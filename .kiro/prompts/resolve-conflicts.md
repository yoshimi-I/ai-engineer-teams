---
name: resolve-conflicts
description: PR のコンフリクトを解消する。
---
# コンフリクト解決

ブランチをリベースし、コンフリクトマーカーを手動解決して force-push する。

## 手順

### 1. 準備
```bash
git fetch origin
git worktree add .worktrees/rebase-<PR番号> <ブランチ名>
cd .worktrees/rebase-<PR番号>
```

### 2. リベース開始
```bash
BASE_BRANCH=$(gh pr view <PR番号> --json baseRefName --jq '.baseRefName')
GIT_EDITOR=true git rebase "origin/${BASE_BRANCH}"
```

### 3. コンフリクト解決
各ファイルについて:
1. ファイル全体を読む
2. `<<<<<<<`, `=======`, `>>>>>>>` マーカーを探す
3. 両方の変更の意図を理解し、正しい結果を書き込む
4. マーカーは一切残さない

```bash
git add <解決したファイル>
GIT_EDITOR=true git rebase --continue
```

### 4. 解決不能な場合
```bash
git rebase --abort
```
人間にエスカレーション。

### 5. push
```bash
git push --force-with-lease origin <ブランチ名>
```

### 6. 後片付け
PRがmergeされた後にのみ、自分が作成したworktreeを削除する。

## ルール

- `--force` ではなく `--force-with-lease` を使う
- メインリポジトリで `git checkout` / `git switch` しない。必ず `.worktrees/` 配下のworktreeで作業する
- コンフリクトマーカーを残したままコミットしない
- 理解せずに片方を丸ごと採用しない
- **vim/nano等のエディタを起動しない** — `git rebase --continue` でエディタが開く場合は `GIT_EDITOR=true git rebase --continue` または `git -c core.editor=true rebase --continue` を使う
- コンフリクト解決はファイルの読み書きツールで行い、エディタコマンドは使わない
