# Issue生成（常に実行 — パイプラインへの引き渡し）

INCEPTIONと8エージェントパイプラインの橋渡し。
設計ドキュメントをエージェントが拾えるGitHub issueに変換する。

## ステップ

### 1. 全INCEPTIONアウトプットを読む
- `aidlc-docs/inception/requirements/requirements.md`
- `aidlc-docs/inception/user-stories/stories.md`（存在する場合）
- `aidlc-docs/inception/architecture/`（存在する場合）

### 2. issueに分解
各issueは:
- 単一のPRで実装可能
- 独立（issue間の依存を最小化）
- テスト可能（明確な受け入れ基準）
- 変更対象ファイル・ディレクトリが明確
- 並列paneで他issueと同時実行しても競合しにくい

#### Pane運用を前提にした分割方針

`kiro-engineer-teams` は8つのpaneを常時起動する前提ではなく、
OrchestratorのAI plannerが状況に応じて必要な役割paneを増減する前提でissueを供給する。

issue生成時は、AI plannerが「どのissueを並列化できるか」を判断できるよう、
依存関係・変更対象・触らない範囲を明確にする。

基本運用:
- `dev-server` はE2E/監視系paneが必要な時にAI plannerが起動する
- `implement` はAI plannerが依存関係・変更範囲・現在のpane状況を見て必要数を起動する
- `review` はPRレビュー/マージ判断が必要な時に起動される
- 依存でblockedなissueは起動対象にしない
- `fix-review` は `CHANGES_REQUESTED` のPRがある場合のみ起動される
- `e2e` はPRや現在状態のブラウザ検証が必要な時に起動される
- `e2e-bug-hunt` はmerge後の検証として起動される
- `watch-main` はmain更新後の回帰検証・bug issue作成に使う
- `watch-main` / `improve` は任意自動化。初期issue生成ではノイズを増やさない

issue分割ルール:
- 1 issue = 1 PR = 1つのユーザー価値または1つの技術的前提
- UI / API / DB / E2E を大きく混ぜない。必要なら依存issueに分ける
- 依存issueは、本文に `depends-on: #<番号>` を書き `blocked` ラベルを付ける
- 依存がないissueは `blocked` を付けない。AI plannerが並列実行可否を判断する
- 複数issueが同じファイルを触る場合は、後続issueに依存関係を明記して同時起動させない
- 並列化できるissueには、本文の「変更対象」に重複しないファイルパスを明記する
- scaffold / domain / API contract / implementation / UI / integration / E2E の順に、上流から下流へ作る
- `improve` が拾うような曖昧な改善はINCEPTION直後に大量生成しない。実装issueが枯れてから扱う

良い分割例:
- `chore: scaffold frontend app`
- `chore: scaffold backend app`
- `feat: add user domain model and validation`
- `feat: add auth API contract`
- `feat: implement login API`
- `feat: implement login screen`
- `test: add login E2E flow`

悪い分割例:
- `feat: implement authentication`
- `feat: build dashboard`
- `feat: connect frontend and backend and add tests`

### 3. 優先順位付け
1. プロジェクトセットアップ / スキャフォールディング（最初に必須）
2. コアドメインモデル / データベーススキーマ
3. バックエンドAPIエンドポイント
4. フロントエンドページ / コンポーネント
5. 統合（フロントエンド↔バックエンド接続）
6. テスト（E2E、追加の統合テスト）
7. ポリッシュ（UI、エラー処理、エッジケース）
8. ドキュメント

### 4. issueを作成
各issueについて:
```bash
gh issue create \
  --title "feat: <簡潔な説明>" \
  --label "優先度" \
  --label "<P0-critical|P1-high|P2-medium|P3-low>" \
  --body "## 説明
<実装内容>

## 受け入れ基準
- [ ] <テスト可能な条件1>
- [ ] <テスト可能な条件2>

## 技術メモ
<関連するアーキテクチャ決定、ファイルパス、依存関係>

## 変更対象
- <主に変更するファイル/ディレクトリ>
- <触らないファイル/境界があれば明記>

## 依存関係
- depends-on: #<番号>（必要な場合のみ）

## 参照
- 要件: aidlc-docs/inception/requirements/requirements.md
- アーキテクチャ: aidlc-docs/inception/architecture/architecture.md"
```

### 5. steeringを更新
確定した技術スタックとプロジェクト規約を
`.kiro/steering/development-rules.md`（プロジェクト固有設定セクション）に記入。

### 6. 状態を更新
`aidlc-docs/aidlc-state.md` を更新:
```
- 現在のフェーズ: INCEPTION ✅ → CONSTRUCTION（パイプライン経由）
- 作成issue数: <件数>
```

### 7. ユーザーに指示
`/quit` と入力してこのセッションを終了するよう伝える。
パイプラインは自動的に起動される。
