# DB設計レビュー

## 目的

実装前にテーブル設計をユーザーに**視覚的に確認**させ、承認を得る。

## 出力形式: DBML（dbdiagram.io 互換）

[dbdiagram.io](https://dbdiagram.io) で直接開けるDBML形式でスキーマを定義し、
HTMLプレビューも生成する。

### 成果物

1. `aidlc-docs/inception/design/schema.dbml` — DBML定義ファイル
2. `aidlc-docs/inception/design/db-diagram.html` — ブラウザで開けるER図

### DBML例

```dbml
Table users {
  id uuid [pk]
  email varchar(255) [unique, not null]
  password_hash varchar(255) [not null, note: 'argon2']
  created_at timestamp [not null, default: `now()`]
}

Table vocabulary {
  id uuid [pk]
  user_id uuid [ref: > users.id, not null]
  word varchar(255) [not null]
  meaning text
  context_sentence text
  source_url varchar(2048)
  type varchar(20) [not null, default: 'word', note: 'word | phrase']
  created_at timestamp [not null, default: `now()`]

  indexes {
    (user_id, created_at) [name: 'idx_vocab_user_created']
    (user_id, word) [unique, name: 'idx_vocab_user_word']
  }
}

Ref: vocabulary.user_id > users.id [delete: cascade]
```

### HTMLプレビュー生成

以下のHTMLを生成し、ブラウザで開いてER図を確認できるようにする:

```html
<!DOCTYPE html>
<html><head>
<title>DB Schema - ER Diagram</title>
<style>
  body { font-family: system-ui; max-width: 1200px; margin: 0 auto; padding: 2rem; background: #1a1a2e; color: #eee; }
  .table { border: 1px solid #4a4a6a; border-radius: 8px; margin: 1rem; display: inline-block; vertical-align: top; min-width: 280px; }
  .table-name { background: #16213e; padding: 0.75rem 1rem; font-weight: bold; border-radius: 8px 8px 0 0; color: #00d4ff; }
  .columns { padding: 0; }
  .column { padding: 0.4rem 1rem; border-top: 1px solid #2a2a4a; display: flex; gap: 1rem; }
  .col-name { flex: 1; font-family: monospace; }
  .col-type { color: #888; font-size: 0.85em; }
  .col-constraint { color: #f0a; font-size: 0.8em; }
  .relations { margin-top: 2rem; padding: 1rem; border: 1px solid #4a4a6a; border-radius: 8px; }
  h1 { color: #00d4ff; }
  h2 { color: #aaa; font-size: 1rem; }
</style>
</head><body>
<h1>Database Schema</h1>
<!-- テーブルごとに .table div を生成 -->
<!-- リレーションを .relations に一覧表示 -->
</body></html>
```

実際のテーブル定義に基づいてHTMLを完成させる。

## 確認ポイント（ユーザーに提示する質問）

1. テーブル間のリレーション（1:N, N:M）は正しいか
2. カラムの型は適切か（VARCHAR長、TIMESTAMP vs DATE、UUID vs SERIAL）
3. 必要なインデックスは定義されているか
4. 正規化レベルは適切か
5. ソフトデリート（deleted_at）は必要か
6. 監査カラム（created_at, updated_at, created_by）は十分か

## 承認フロー

1. DBML + HTMLを生成してユーザーに提示
2. 「ブラウザで `db-diagram.html` を開いて確認してください」と案内
3. フィードバックを受けて修正
4. 明示的な承認（「OK」「承認」「進めて」）を得る
5. 承認後、DBMLファイルをコミット

## 後続への影響

承認されたDBMLは:
- issue生成時のマイグレーションissueの仕様になる
- implement agentがスキーマ実装時に参照する
- integration-audit agentがin-memory stub残存を検出する基準になる
