# UI設計レビュー

## 目的

実装前に主要画面のモックアップを**ブラウザで開ける HTML/CSS** で作成し、
ユーザーに確認させて承認を得る。

## 成果物

```
aidlc-docs/inception/design/mockups/
  ├── index.html          ← 全画面へのリンク集（ナビゲーション）
  ├── login.html
  ├── signup.html
  ├── dashboard.html
  ├── [機能名].html
  └── styles.css          ← 共通スタイル（1ファイルで完結）
```

加えて:
- `aidlc-docs/inception/design/screen-flow.md` — 画面遷移図（mermaid）
- `aidlc-docs/inception/design/components.md` — コンポーネント構成

## HTML モックアップのルール

### 必須要件

1. **ブラウザで直接開ける** — ビルド不要、ダブルクリックで表示
2. **外部CDN依存は最小限** — Google Fonts程度はOK、フレームワークは不可
3. **レスポンシブ** — モバイル/デスクトップ両方で確認可能
4. **ダミーデータ入り** — 空の枠ではなく実際のデータが入った状態
5. **インタラクション不要** — 静的HTML。JSは画面遷移リンクのみ
6. **デザインビジョン準拠** — ステージ4で決めたカラー/トーン/UIキットに従う

### テンプレート

```html
<!DOCTYPE html>
<html lang="ja">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>[画面名] - [プロダクト名]</title>
  <link rel="stylesheet" href="styles.css">
</head>
<body>
  <nav class="nav">
    <a href="index.html">← 全画面一覧</a>
    <span class="nav-title">[画面名]</span>
  </nav>
  <main class="container">
    <!-- 画面の内容 -->
  </main>
</body>
</html>
```

### styles.css の方針

```css
/* デザインビジョンで決めたカラーパレット */
:root {
  --color-primary: #...;
  --color-bg: #...;
  --color-text: #...;
  --color-border: #...;
  --radius: 8px;
  --font-main: 'Inter', system-ui, sans-serif;
}

/* モバイルファースト */
.container { max-width: 1200px; margin: 0 auto; padding: 1rem; }

@media (min-width: 768px) {
  .container { padding: 2rem; }
}
```

## 画面遷移図

```markdown
\`\`\`mermaid
graph TD
    Login[ログイン] --> Dashboard[ダッシュボード]
    Signup[新規登録] --> Dashboard
    Dashboard --> VocabList[単語一覧]
    Dashboard --> Quiz[クイズ]
    Dashboard --> Settings[設定]
    VocabList --> WordDetail[単語詳細]
    Quiz --> QuizResult[結果]
\`\`\`
```

## コンポーネント構成

各画面で使うコンポーネントを一覧化:

```markdown
## Dashboard
- Header（ユーザー名、ログアウト）
- StatsCard × 3（学習単語数、連続日数、正答率）
- RecentWords（直近5件）
- QuickActions（クイズ開始、単語追加）

## VocabularyList
- Header
- SearchBar + FilterTabs（全部/単語/フレーズ）
- WordCard × N（単語、意味、ソース、日付）
- Pagination
```

## 確認ポイント（ユーザーに提示する質問）

1. 画面の情報配置は期待通りか
2. 導線（どこからどこに遷移するか）は自然か
3. モバイルでの使い勝手は問題ないか
4. 色・フォント・余白はデザインビジョンと一致しているか
5. 足りない画面/要素はないか

## 承認フロー

1. 全画面のHTMLモックアップを生成
2. 「`mockups/index.html` をブラウザで開いて確認してください」と案内
3. 画面ごとにフィードバックを受ける
4. 修正して再提示
5. 明示的な承認を得る

## 後続への影響

承認されたモックアップは:
- implement agentがUI実装時のデザイン仕様になる
- コンポーネント構成がissue分割の基準になる
- ui-audit agentがデザイン品質を判定する基準になる
