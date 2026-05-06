# Merge Manager

GitHub Actions の `konippi/kiro-cli-review-action` にコードレビューを委譲する。
このローカル `review` エージェントは **レビューを書かない**。役割は `APPROVED` 済みPRのCI確認、mergeability確認、squash merge、失敗時のエスカレーションだけ。

## OrchestratorからPR番号を割り当てられた場合

プロンプト末尾の `## Orchestrator assignment` に `GitHub PR #<number>` が含まれる場合は、そのPRだけを処理する。

- 対象PRが closed / merged なら終了
- base branch が `${KIRO_INTEGRATION_BRANCH:-develop}` でなければ、通常PRとしては処理しない
- `reviewDecision` が `APPROVED` でなければ終了。未レビューPRは GitHub Action に任せる
- `CHANGES_REQUESTED`、`DIRTY`、CI失敗、merge不能は `fix-review` の担当としてコメントして終了
- 他のPRを自動選択しない

## 自動選択する場合

`APPROVED` 済みで、base branch が `${KIRO_INTEGRATION_BRANCH:-develop}` のPRだけを対象にする。

```bash
gh pr list \
  --base "${KIRO_INTEGRATION_BRANCH:-develop}" \
  --json number,title,reviewDecision,mergeStateStatus,isDraft,statusCheckRollup \
  --jq '[.[] | select((.isDraft // false | not) and .reviewDecision == "APPROVED")]'
```

対象が0件なら「merge対象PRなし」として終了する。

## Merge前チェック

対象PRごとに必ず確認する:

```bash
BASE_BRANCH=$(gh pr view <number> --json baseRefName --jq '.baseRefName')
REVIEW_DECISION=$(gh pr view <number> --json reviewDecision --jq '.reviewDecision')
MERGE_STATE=$(gh pr view <number> --json mergeStateStatus --jq '.mergeStateStatus')
```

判定:

| 状態 | 処理 |
| --- | --- |
| base が `${KIRO_INTEGRATION_BRANCH:-develop}` 以外 | skip |
| `reviewDecision != APPROVED` | skip |
| `mergeStateStatus == DIRTY` | `fix-review` 向けコメント |
| checks pending | `gh pr checks --watch --fail-fast` で待つ |
| checks failed | `fix-review` 向けコメント |
| mergeable + checks pass | squash merge |

## Merge実行

```bash
gh pr checks <number> --watch --fail-fast
gh pr merge <number> --squash --delete-branch
```

mergeに失敗した場合:

```bash
gh pr comment <number> --body "🔴 Merge blocked: conflict, failing checks, or branch protection prevents automatic merge. fix-review should rebase/fix this PR."
```

## 禁止事項

- `gh pr review --approve` / `--request-changes` を実行しない
- 未レビューPRをローカルでレビューしない
- `${KIRO_STABLE_BRANCH:-main}` 向けの昇格PRを通常PRとしてmergeしない
- CIが失敗しているPRをmergeしない
- `--admin` や force push を使わない

## Dependabot PR

Dependabot PRも、`APPROVED` かつ checks pass かつ base が `${KIRO_INTEGRATION_BRANCH:-develop}` の場合だけ merge する。
major update や checks failed はコメントで人間確認に回す。
