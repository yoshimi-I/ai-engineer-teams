# ドメインモデリング（イベントストーミング）

## 目的

要件分析とアーキテクチャ設計の間で、**AI側がイベントストーミングを実施**し、
ドメインの構造を可視化してユーザーに確認させる。

## いつ実行するか

- バックエンドがある場合は必須
- CRUD以上の業務ロジックがある場合は特に重要
- ステージ5（アーキテクチャ設計）の前に実施

## イベントストーミングの要素（色分け）

| 要素 | 色 | 説明 |
|------|-----|------|
| **ドメインイベント** | オレンジ | 過去形のビジネス事象（例: 「注文が確定された」） |
| **コマンド** | 青 | イベントを引き起こすアクション（例: 「注文を確定する」） |
| **集約** | 黄 | 不変条件を持つビジネスエンティティ |
| **リードモデル** | 緑 | 意思決定に必要なUI表示/データ |
| **外部システム** | ピンク | サードパーティシステム |
| **ポリシー/ビジネスルール** | 紫 | 「イベントが起きたら→コマンドを実行」の自動反応 |
| **ホットスポット** | 赤 | 未解決の矛盾・疑問・摩擦 |
| **アクター** | 濃い黄 | コマンドを発行する人物/ペルソナ |

## イベントの3つのトリガー源

1. **アクター** — 人間がコマンドを発行
2. **外部システム** — 外部からイベント/コマンドが到着
3. **タイマー/スケジュール** — 時間経過で発火

## 実施手順

### Phase 1: カオス探索（発散）

要件から「システム内で起きること」を**過去形で**大量に列挙する。
順序は気にしない。とにかく出す。

```
例:
- ユーザーが登録された (UserRegistered)
- 単語が保存された (WordSaved)
- クイズが開始された (QuizStarted)
- クイズが回答された (QuizAnswered)
- 学習目標が達成された (GoalAchieved)
- サブスクリプションが開始された (SubscriptionStarted)
```

### Phase 2: タイムライン整理

イベントを時系列に並べ、重複を除去し、ギャップを埋める。

**逆方向ナラティブ**: 最後から最初に向かって歩き、
「このイベントが起きるには、その前に何が必要？」を確認。
→ 抜けているイベントが見つかる。

### Phase 3: ピボタルイベントの特定

フロー全体で最も重要なイベントを特定。これが境界づけられたコンテキストの
境界になることが多い。

例: 「注文が確定された」「支払いが完了した」「商品が発送された」

### Phase 4: コマンドの特定

各イベントを引き起こす「アクション」を特定:

```
アクター → コマンド → イベント
ユーザー → RegisterUser → UserRegistered
ユーザー → SaveWord → WordSaved
システム → CheckGoalProgress → GoalAchieved（ポリシー）
```

### Phase 5: 集約の特定

関連するイベントとコマンドをグループ化し、整合性の境界（トランザクション境界）を決める:

```
[User集約]
  - RegisterUser → UserRegistered
  - UpdateProfile → ProfileUpdated

[Vocabulary集約]
  - SaveWord → WordSaved
  - DeleteWord → WordDeleted
  不変条件: 同一ユーザーの同一単語は重複不可

[Quiz集約]
  - StartQuiz → QuizStarted
  - AnswerQuestion → QuizAnswered
  - CompleteQuiz → QuizCompleted
  不変条件: 開始済みクイズのみ回答可能
```

### Phase 6: ポリシーの特定

「イベントが起きたら自動的にコマンドを実行する」パターン:

```
WHEN QuizCompleted THEN CheckAchievements（ポリシー）
WHEN WordSaved THEN UpdateGoalProgress（ポリシー）
WHEN PaymentFailed THEN SuspendSubscription（ポリシー）
```

ポリシーはSaga/Choreographyの候補になる。

### Phase 7: 境界づけられたコンテキストの決定

集約をさらにグループ化。以下のパターンで境界を認識する:

| パターン | 説明 |
|---------|------|
| 言語の境界 | 同じ概念に異なる用語を使う箇所 |
| 時間の境界 | ピボタルイベントの前後 |
| 組織の境界 | 担当チーム/部門が変わる箇所 |
| データの境界 | 異なるデータストアが自然な箇所 |

```
[認証コンテキスト]
  └── User集約

[学習コンテキスト]
  ├── Vocabulary集約
  └── Quiz集約

[ゲーミフィケーションコンテキスト]
  ├── Achievement集約
  └── Goal集約
```

### Phase 8: DDDとの対応

| イベントストーミング要素 | DDDコンセプト |
|------------------------|--------------|
| ドメインイベント（オレンジ） | Domain Events |
| 集約（黄） | Aggregates |
| コマンド（青） | Command Handlers |
| ポリシー（紫） | Domain Services / Saga |
| リードモデル（緑） | CQRS Query Side |
| 外部システム（ピンク） | Anti-Corruption Layer |
| コンテキスト境界 | Strategic Design |

## HTML成果物の生成

`aidlc-docs/inception/design/event-storming.html` を生成:

```html
<!DOCTYPE html>
<html lang="ja"><head>
<meta charset="UTF-8">
<title>Event Storming - ドメインモデル</title>
<style>
  body { font-family: system-ui; max-width: 1400px; margin: 0 auto; padding: 2rem; background: #0d1117; color: #e6edf3; }
  .board { display: flex; gap: 2rem; flex-wrap: wrap; }
  .context { border: 2px solid #30363d; border-radius: 12px; padding: 1.5rem; min-width: 300px; flex: 1; }
  .context-name { font-size: 1.2rem; font-weight: bold; margin-bottom: 1rem; color: #58a6ff; }
  .aggregate { background: #161b22; border: 1px solid #30363d; border-radius: 8px; padding: 1rem; margin-bottom: 1rem; }
  .aggregate-name { font-weight: bold; color: #f0883e; margin-bottom: 0.5rem; }
  .event { display: inline-block; background: #f97316; color: #000; padding: 0.3rem 0.8rem; border-radius: 4px; margin: 0.2rem; font-size: 0.85rem; font-weight: 500; }
  .command { display: inline-block; background: #3b82f6; color: #fff; padding: 0.3rem 0.8rem; border-radius: 4px; margin: 0.2rem; font-size: 0.85rem; }
  .policy { display: inline-block; background: #a855f7; color: #fff; padding: 0.3rem 0.8rem; border-radius: 4px; margin: 0.2rem; font-size: 0.85rem; }
  .read-model { display: inline-block; background: #22c55e; color: #000; padding: 0.3rem 0.8rem; border-radius: 4px; margin: 0.2rem; font-size: 0.85rem; }
  .external { display: inline-block; background: #ec4899; color: #fff; padding: 0.3rem 0.8rem; border-radius: 4px; margin: 0.2rem; font-size: 0.85rem; }
  .hotspot { display: inline-block; background: #ef4444; color: #fff; padding: 0.3rem 0.8rem; border-radius: 4px; margin: 0.2rem; font-size: 0.85rem; }
  .invariant { color: #6e7681; font-size: 0.8rem; font-style: italic; margin-top: 0.5rem; }
  .flow { margin-top: 2rem; padding: 1.5rem; border: 2px solid #30363d; border-radius: 12px; }
  .flow-title { font-size: 1.1rem; font-weight: bold; color: #58a6ff; margin-bottom: 1rem; }
  .flow-step { display: flex; align-items: center; gap: 0.5rem; margin: 0.5rem 0; flex-wrap: wrap; }
  .arrow { color: #6e7681; }
  h1 { color: #58a6ff; }
  .legend { display: flex; gap: 1rem; margin-bottom: 2rem; padding: 1rem; background: #161b22; border-radius: 8px; flex-wrap: wrap; }
  .legend-item { display: flex; align-items: center; gap: 0.5rem; font-size: 0.85rem; }
  .policies-section { margin-top: 2rem; padding: 1.5rem; border: 2px solid #30363d; border-radius: 12px; }
</style>
</head><body>
<h1>🎯 Event Storming</h1>
<div class="legend">
  <div class="legend-item"><span class="command">Command</span> コマンド</div>
  <div class="legend-item"><span class="event">Event</span> イベント</div>
  <div class="legend-item"><span class="policy">Policy</span> ポリシー</div>
  <div class="legend-item"><span class="read-model">Read Model</span> 読み取り</div>
  <div class="legend-item"><span class="external">External</span> 外部</div>
  <div class="legend-item"><span class="hotspot">Hot Spot</span> 未解決</div>
</div>
<div class="board">
  <!-- 各コンテキスト・集約・イベント・コマンド・ポリシーをここに展開 -->
</div>
<div class="policies-section">
  <div class="flow-title">ポリシー（自動反応ルール）</div>
  <!-- WHEN event THEN command のリスト -->
</div>
<div class="flow">
  <div class="flow-title">主要フロー（タイムライン）</div>
  <!-- ユーザーの主要操作フローを時系列で表示 -->
</div>
</body></html>
```

## ユーザーへの提示

1. HTML成果物を生成
2. 「`event-storming.html` をブラウザで開いて確認してください」と案内
3. 以下を質問:
   - コンテキストの分割は適切か（分けすぎ/まとめすぎ）
   - 見落としているイベントはないか
   - ポリシー（自動反応）は正しいか
   - ホットスポット（未解決の疑問）はあるか
   - 集約の不変条件は正しいか
4. フィードバックを受けて修正
5. 承認を得る

## 後続への影響

承認されたドメインモデルは:
- **ディレクトリ構成**に直結（コンテキスト → モジュール/ディレクトリ）
- **DB設計**の集約境界になる（集約 = トランザクション境界）
- **API設計**のリソース分割になる（集約 ≒ APIリソース）
- **issue分割**の単位になる（集約ごとに垂直スライス）
- **ポリシー**はイベント駆動アーキテクチャの設計根拠になる

```
src/
  domain/
    auth/          ← 認証コンテキスト
      user.ts
    learning/      ← 学習コンテキスト
      vocabulary.ts
      quiz.ts
    gamification/  ← ゲーミフィケーションコンテキスト
      achievement.ts
      goal.ts
```

## アンチパターン

- ❌ CRUDだけでイベントを考える（「保存された」だけでなく業務的な意味を考える）
- ❌ 技術的な関心事をドメインに混ぜる（「DBに書き込まれた」はイベントではない）
- ❌ 全部1つのコンテキストにまとめる（境界を引かないとモノリスになる）
- ❌ コンテキストを細かく分けすぎる（CRUD程度なら1コンテキストで十分）
- ❌ ポリシーを見落とす（「〜したら自動的に〜する」は重要な業務ルール）
- ❌ 不変条件を定義しない（集約の存在意義が不明確になる）
- ❌ ホットスポットを無視する（未解決の疑問は実装時に必ず問題になる）
