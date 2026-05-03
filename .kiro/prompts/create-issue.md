
# Issue作成スキル — 実装者が迷わない詳細issueを書く

## Philosophy

issueの質 = 実装速度。「調査済み・方針決定済み・ファイルパス特定済み」のissueを書く。

## Process

### Step 1: 要望の明確化
- 何を実現したいか、なぜ必要か、スコープを整理
- 不明点は選択肢とメリデメを提示して質問。丸投げの質問は禁止

### Step 2: コードベース徹底調査
最低5ファイル以上読んでからissueを書く:
1. 変更対象ファイル
2. 呼び出し元/依存先
3. 型定義・インターフェース
4. 既存の類似実装
5. テストファイル

### Step 3: 既存issue重複チェック
```bash
gh issue list --state open --limit 50 --json number,title
gh issue list --state closed --limit 30 --json number,title
```

### Step 4: Issue本文作成
実装者が読むだけで実装に入れるレベルで書く:
- 概要、背景・動機、現状の実装
- 変更方針（ファイルパス付きチェックリスト）
- テスト、技術的な注意事項、影響範囲、受け入れ条件

### Step 4.5: Pane運用に合わせた分割確認
`kiro-engineer-teams` は、OrchestratorのAI plannerが必要なpane数を判断して短命に起動する。
issueは「8paneを常時埋める」ためではなく、AIが並列実行可否を判断でき、`implement` paneが迷わず1PRで完了できる粒度に分割する。

分割基準:
- 1 issue = 1 PR = 1つのユーザー価値、または1つの技術的前提
- 依存がないready issueは並列候補。AI plannerが変更対象・依存・現在のpane状況を見てpane数を決める
- 並列実行を狙うissueは、変更対象ファイル/ディレクトリが重ならないようにする
- UI / API / DB / E2E を大きく混ぜない。必要なら別issueに分ける
- 同じファイルを触るissueは、後続issue本文に `depends-on: #<番号>` を書き `blocked` ラベルを付ける
- `fix-review` はレビュー指摘時、`e2e-bug-hunt` はmerge後に起動される前提で、通常issueに混ぜすぎない
- `improve` 向けの曖昧な改善issueは、実装issueが残っている間は増やさない

本文には必ず以下を含める:
- `## 変更対象`: 主に触るファイル/ディレクトリ
- `## 触らない範囲`: 競合防止の境界
- `## 依存関係`: `depends-on: #<番号>` がある場合のみ

### Step 5: ラベル選定・Issue作成
`gh issue create` で作成。タイトルはConventional Commits準拠。

## Rules

- 調査せずにissueを書かない。最低5ファイルは読む
- 変更方針のチェックリストは必ずファイルパス付き
- 大きすぎるissueは分割する。1 issue = 1 PR で完結するスコープに
- pane数を増やすためにissueを水増ししない。Orchestratorの短命pane運用に合う、独立・小粒・テスト可能なissueにする
- 変更対象が重なるissueは依存関係を明記し、同時着手されないようにする
