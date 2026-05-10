# 設計成果物レビュー

INCEPTION のアーキテクチャ設計が承認された後、**実装に入る前に具体的な設計成果物を
作成してユーザーの承認を得る**ステージ。

## なぜ必要か

抽象的なアーキテクチャ方針だけで実装に入ると：
- テーブル設計が意図と違う（カラム名、リレーション、正規化レベル）
- APIのURL設計が使いにくい（RESTful でない、命名が不統一）
- UIの画面構成がユーザーの想定と違う（導線、情報配置）

これらは実装後に発覚すると大規模な手戻りになる。**実装前に具体物で合意する**。

## DB設計

### 出力形式

mermaid ER図 + テーブル定義表:

```markdown
## ER図

\`\`\`mermaid
erDiagram
    USER ||--o{ VOCABULARY : saves
    USER ||--o{ BOOKMARK : bookmarks
    VOCABULARY {
        uuid id PK
        uuid user_id FK
        string word
        string meaning
        string context_sentence
        string source_url
        timestamp created_at
    }
\`\`\`

## テーブル定義

### users
| カラム | 型 | 制約 | 説明 |
|--------|-----|------|------|
| id | UUID | PK | |
| email | VARCHAR(255) | UNIQUE, NOT NULL | |
| password_hash | VARCHAR(255) | NOT NULL | argon2 |
| created_at | TIMESTAMP | NOT NULL, DEFAULT NOW() | |

### インデックス
- `idx_users_email` ON users(email)
```

### 確認ポイント
- テーブル間のリレーション（1:N, N:M）は正しいか
- カラムの型は適切か（VARCHAR長、TIMESTAMP vs DATE）
- 必要なインデックスは定義されているか
- 正規化レベルは適切か（過剰正規化 vs 非正規化）

## API設計

### 出力形式

エンドポイント一覧表 + リクエスト/レスポンス例:

```markdown
## エンドポイント一覧

| メソッド | パス | 認証 | 説明 |
|---------|------|------|------|
| POST | /auth/signup | 不要 | ユーザー登録 |
| POST | /auth/login | 不要 | ログイン |
| GET | /words | 必須 | 単語一覧取得 |
| POST | /words | 必須 | 単語保存 |
| DELETE | /words/:id | 必須 | 単語削除 |

## リクエスト/レスポンス例

### POST /auth/login
Request:
\`\`\`json
{ "email": "user@example.com", "password": "..." }
\`\`\`
Response (200):
\`\`\`json
{ "token": "eyJ...", "user": { "id": "...", "email": "..." } }
\`\`\`
Response (401):
\`\`\`json
{ "error": "Invalid credentials" }
\`\`\`
```

### 確認ポイント
- URL命名は一貫しているか（複数形、ネスト深度）
- 認証が必要なエンドポイントは明確か
- エラーレスポンスの形式は統一されているか
- ページネーション、フィルタリングの設計は適切か

## UI設計

### 出力形式

主要画面ごとにHTML/CSSのモックアップファイルを作成:

```
aidlc-docs/inception/design/mockups/
  ├── login.html
  ├── signup.html
  ├── dashboard.html
  ├── vocabulary-list.html
  └── quiz.html
```

各HTMLファイルは：
- インラインCSSで完結（外部依存なし）
- ブラウザで直接開いて確認可能
- レスポンシブ対応（モバイル/デスクトップ）
- ダミーデータで実際の見た目を再現

加えて画面遷移図:

```markdown
\`\`\`mermaid
graph LR
    Login --> Dashboard
    Signup --> Dashboard
    Dashboard --> VocabularyList
    Dashboard --> Quiz
    VocabularyList --> WordDetail
\`\`\`
```

### 確認ポイント
- 画面の情報配置はユーザーの期待通りか
- 導線（どこからどこに遷移するか）は自然か
- モバイルでの使い勝手は考慮されているか
- デザインビジョン（ステージ4）と一貫しているか

## 承認フロー

1. 成果物を作成してチャットで提示
2. ユーザーのフィードバックを受ける
3. 修正して再提示
4. 「OK」「承認」「進めて」等の明示的承認を得る
5. 次の成果物へ（または全承認ならissue生成へ）

**部分承認OK**: 「DBはいいけどAPIのURL変えて」→ DBは確定、APIだけ修正

## アンチパターン

- ❌ 成果物を見せずにissue生成に進む
- ❌ 「問題なければ進みます」と言って沈黙を承認とみなす
- ❌ 全成果物を一度に出して「全部OKですか？」と聞く（1つずつ確認）
- ❌ HTMLモックを作らずテキストだけで画面を説明する
