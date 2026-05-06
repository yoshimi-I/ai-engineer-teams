# 8-Agent 並列自動化パイプライン

8つのKiro CLIセッションを並列で起動し、issue→実装→レビュー→マージ→検証の全サイクルを自動化する。

## アーキテクチャ

```
[Agent 1] /implement ──────── issue→実装→PR作成
[Agent 2] /implement ──────── 同上（並列で別issue）
[Agent 3] /review ─────────── open PR→厳格レビュー→マージ
[Agent 4] /review ─────────── 同上（並列で別PR）
[Agent 5] /fix-review── 🔴指摘→修正→再push
[Agent 6] /watch-main ─────── developマージ検出→E2E検証→main昇格 or バグissue
[Agent 7] /e2e-bug-hunt ───── Playwright巡回→バグissue
[Agent 8] /ui-audit ────────── デザイン品質監査→design-review issue
[Agent 9] /improve ─────────── コード分析→改善issue自動生成

※ CI失敗はpre-commitで防止、発生時はImpl自身が修正
共有状態: issue/task.md
```

## データフロー

```
GitHub Issue
    │
    ▼
Agent 1,2: /implement ──→ PR作成（pre-commitでlint/test通過済み）
                             │
                             ▼
                       Agent 3,4: /review
                             │
                        ┌────┴────┐
                     🟢 LGTM   🔴 修正必須
                        │         │
                        ▼         ▼
                   merge    Agent 5: /fix-review
                        │         │
                        │    修正→push→Agent 3,4が再レビュー
                        │
                        ▼
                   develop にマージ
                        │
                        ▼
                   Agent 6: /watch-main（E2E検証）
                        │
                   バグ発見? → Yes → issue作成 → Agent 1,2 が拾う
                                        ▲
                                        │
                   Agent 7: /e2e-bug-hunt（Playwright巡回）
                   Agent 8: /ui-audit（デザイン品質監査）

Agent 9: /improve（10分間隔で改善issue自動生成）
```

## 起動方法

8つのターミナルでそれぞれ起動:

```bash
# Terminal 1-2: 実装エージェント
kiro-cli chat → /implement

# Terminal 3-4: レビューエージェント
kiro-cli chat → /review

# Terminal 5: レビュー指摘修正エージェント
kiro-cli chat → /fix-review

# Terminal 6: mainブランチ監視エージェント
kiro-cli chat → /watch-main

# Terminal 7: E2Eバグハントエージェント
kiro-cli chat → /e2e-bug-hunt

# Terminal 8: 改善issue自動生成エージェント
kiro-cli chat → /improve
```

## 各エージェントの役割

| #   | プロンプト      | 役割                                                   | ポーリング間隔 |
| --- | --------------- | ------------------------------------------------------ | -------------- |
| 1   | `/implement`    | issueを取って実装→PR作成（ループ）                     | 即座に次へ     |
| 2   | `/implement`    | 同上（並列で別issue）                                  | 即座に次へ     |
| 3   | `/review`       | open PRを取得→厳格レビュー→マージ + Dependabot PR処理  | 即座に次へ     |
| 4   | `/review`       | 同上（並列で別PR）                                     | 即座に次へ     |
| 5   | `/fix-review`   | 🔴指摘のあるPRを修正→再push                            | 2分            |
| 6   | `/watch-main`   | developマージ検出→テスト+E2E検証→main昇格 or バグissue | 2分            |
| 7   | `/e2e-bug-hunt` | Playwright全ページ巡回→バグissue                       | サイクル完了後 |
| 8   | `/ui-audit`     | デザイン品質監査→design-review issue                   | merge後        |
| 9   | `/improve`      | コード分析→改善issue自動生成                           | 10分           |

## CI失敗の対応方針

Fix-CIエージェントは廃止。代わりに:

- **pre-commit**: Implエージェントはコミット前に必ずlint/testを実行（steeringで強制）
- **CI失敗時**: PRを作成したImplエージェント自身が修正する
- **レビュー時**: Reviewエージェントがpre-commit未実行を検出した場合はREQUEST CHANGES

## 競合回避

排他制御の主体は **GitHub issueのassignee**（APIがアトミックなので同時書き込み競合しない）。
`issue/task.md` はローカルの補助記録として併用。

- `/implement` は着手前にassigneeが空か確認 → 空なら `--add-assignee @me` で即ロック → task.mdも更新
- `/review` はレビューのみ行い、コードを変更しない（競合しない）
- `/fix-review` は task.md で他エージェントが触っていないPRのみ修正
- `/watch-main` はissue作成のみ（競合しない）
- `/e2e-bug-hunt` はissue作成のみ（競合しない）
- `/improve` はissue作成のみ（競合しない）

## エスカレーション

| エージェント    | エスカレーション条件       | 方法                     |
| --------------- | -------------------------- | ------------------------ |
| `/fix-review`   | 3回修正しても🔴            | PRにコメント             |
| `/e2e-bug-hunt` | アプリ起動不能             | 報告して停止             |
| `/improve`      | 改善ポイントが見つからない | スキップして次サイクルへ |
| `/watch-main`   | アプリ起動不能             | 報告して停止             |
