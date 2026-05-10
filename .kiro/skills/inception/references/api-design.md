# API設計レビュー

## 目的

実装前にAPI仕様をユーザーに**UIで確認**させ、承認を得る。
APIの種類に応じて適切なツールで可視化する。

## Step 1: APIスタイルの確認

ユーザーに以下を質問する:

> APIのスタイルはどれですか？
> 1. **REST** — Swagger UI で仕様を確認
> 2. **GraphQL** — GraphQL Playground で確認
> 3. **gRPC** — Buf Schema Registry 形式で確認
> 4. **混合** — メインのスタイルを選択

## REST → OpenAPI + Swagger UI

### 成果物

1. `aidlc-docs/inception/design/openapi.yaml` — OpenAPI 3.0 仕様
2. `aidlc-docs/inception/design/api-docs.html` — Swagger UI（ブラウザで開ける）

### OpenAPI例

```yaml
openapi: 3.0.3
info:
  title: Netflix English Learning API
  version: 0.1.0
paths:
  /auth/signup:
    post:
      summary: ユーザー登録
      requestBody:
        required: true
        content:
          application/json:
            schema:
              type: object
              required: [email, password]
              properties:
                email: { type: string, format: email }
                password: { type: string, minLength: 8 }
      responses:
        '201':
          description: 登録成功
          content:
            application/json:
              schema:
                type: object
                properties:
                  token: { type: string }
                  user: { $ref: '#/components/schemas/User' }
        '409':
          description: メールアドレス重複
```

### Swagger UI HTML

```html
<!DOCTYPE html>
<html><head>
<title>API Specification - Swagger UI</title>
<link rel="stylesheet" href="https://unpkg.com/swagger-ui-dist@5/swagger-ui.css">
</head><body>
<div id="swagger-ui"></div>
<script src="https://unpkg.com/swagger-ui-dist@5/swagger-ui-bundle.js"></script>
<script>
SwaggerUIBundle({
  spec: /* OpenAPI YAML をここに JSON 変換して埋め込む */,
  dom_id: '#swagger-ui',
  presets: [SwaggerUIBundle.presets.apis, SwaggerUIBundle.SwaggerUIStandalonePreset],
  layout: "BaseLayout"
});
</script>
</body></html>
```

実際にはOpenAPI YAMLの内容をJSON化してspec部分に埋め込む。

## GraphQL → Playground HTML

### 成果物

1. `aidlc-docs/inception/design/schema.graphql` — GraphQL スキーマ定義
2. `aidlc-docs/inception/design/api-docs.html` — GraphQL Playground（スキーマ表示）

### スキーマ例

```graphql
type Query {
  me: User!
  words(limit: Int = 20, offset: Int = 0): WordConnection!
  word(id: ID!): Word
}

type Mutation {
  signup(input: SignupInput!): AuthPayload!
  login(input: LoginInput!): AuthPayload!
  saveWord(input: SaveWordInput!): Word!
  deleteWord(id: ID!): Boolean!
}

type User {
  id: ID!
  email: String!
  createdAt: DateTime!
}

type Word {
  id: ID!
  word: String!
  meaning: String
  contextSentence: String
  sourceUrl: String
  type: WordType!
  createdAt: DateTime!
}

enum WordType { WORD PHRASE }
```

### Playground HTML

```html
<!DOCTYPE html>
<html><head>
<title>API Specification - GraphQL</title>
<link rel="stylesheet" href="https://unpkg.com/graphql-playground-react/build/static/css/index.css">
</head><body>
<div id="root"></div>
<script src="https://unpkg.com/graphql-playground-react/build/static/js/middleware.js"></script>
<script>
GraphQLPlayground.init(document.getElementById('root'), {
  schema: `/* schema.graphql の内容をここに埋め込む */`,
  settings: { 'schema.polling.enable': false }
});
</script>
</body></html>
```

## gRPC → Proto + HTML ドキュメント

### 成果物

1. `aidlc-docs/inception/design/service.proto` — Protocol Buffers 定義
2. `aidlc-docs/inception/design/api-docs.html` — Proto ドキュメント（HTML）

### Proto例

```protobuf
syntax = "proto3";
package english_learning.v1;

service AuthService {
  rpc Signup(SignupRequest) returns (AuthResponse);
  rpc Login(LoginRequest) returns (AuthResponse);
}

service VocabularyService {
  rpc SaveWord(SaveWordRequest) returns (Word);
  rpc ListWords(ListWordsRequest) returns (ListWordsResponse);
  rpc DeleteWord(DeleteWordRequest) returns (google.protobuf.Empty);
}

message Word {
  string id = 1;
  string word = 2;
  string meaning = 3;
  string context_sentence = 4;
  string source_url = 5;
  WordType type = 6;
}
```

### HTML ドキュメント

サービス/メソッド/メッセージを一覧表示するHTMLを生成。
スタイルはDB設計のHTMLと統一する。

## 確認ポイント（ユーザーに提示する質問）

1. エンドポイント/クエリの命名は直感的か
2. 認証が必要な操作は明確か
3. エラーレスポンスの形式は統一されているか
4. ページネーション/フィルタリングの設計は適切か
5. バージョニング戦略は必要か（/v1/ prefix等）

## 承認フロー

1. APIスタイルを確認
2. 仕様ファイル + UI HTMLを生成
3. 「ブラウザで `api-docs.html` を開いて確認してください」と案内
4. フィードバックを受けて修正
5. 明示的な承認を得る
6. 承認後、仕様ファイルをコミット

## 後続への影響

承認されたAPI仕様は:
- implement agentがルート実装時に参照する正式な仕様
- フロントエンドのAPI呼び出しURLの正解
- integration-audit agentがURL不一致を検出する基準
