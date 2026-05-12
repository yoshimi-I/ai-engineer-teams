---
name: improve
description: コードベースを分析してプロダクト改善のための issue を自動生成する。
---
# プロダクト改善issue自動生成

ユーザーの指示を待たず、即座にコードベースの分析を開始する。プロダクトをより良くするための改善issueを自動生成する。

## 1サイクルの処理

### Step 1: 現状分析

1. プロジェクト構成を把握:
   ```bash
   find . -type f -not -path './.git/*' -not -path './node_modules/*' | head -100
   ```
2. 既存issueを確認（重複防止）:
   ```bash
   gh issue list --state all --json number,title --jq '.[].title'
   ```
3. 最近のコミットから開発の方向性を把握:
   ```bash
   git log --oneline -20
   ```

### Step 2: 改善ポイントを特定

以下の観点でコードを分析し、1サイクルにつき1〜2件の改善issueを作成:

| 観点 | 例 |
|------|-----|
| DX改善 | ビルド高速化、開発環境改善、エラーメッセージ改善 |
| コード品質 | リファクタリング、型安全性向上、テストカバレッジ |
| パフォーマンス | ボトルネック解消、キャッシュ導入、バンドルサイズ削減 |
| セキュリティ | 脆弱性対策、依存関係更新、入力バリデーション強化 |
| ユーザー体験 | アクセシビリティ、レスポンシブ対応、エラーハンドリング |
| ドキュメント | README改善、API仕様書、コメント追加 |

### Step 3: コンフリクトチェック

既存のopen issueと変更対象が重複しないか確認:
```bash
gh issue list --state open --json number,title,body
```
- 重複なし → 独立issueとして作成
- 重複あり → `depends-on: #<number>` を本文に記載し `blocked` ラベルを付与

### Step 4: issue作成

```bash
gh issue create \
  --title "improve: <具体的なタイトル>" \
  --label "enhancement" \
  --label "優先度" \
  --label "<P0-critical|P1-high|P2-medium|P3-low>" \
  --body "<改善の背景・理由・期待効果を記述>"
```

## ルール

- 既存issueと重複するものは作らない
- 抽象的な提案ではなく、具体的で実行可能なissueにする
- **1サイクルで作成するissueは最大3件まで** — 上限に達したらサイクル終了
- 優先度の高いもの（セキュリティ、バグに近いもの）を優先
- `gh issue close` は禁止 — issueを閉じる権限はない
