
# INCEPTION — 構造化プロジェクト計画

INCEPTIONフェーズを実行する: ワークスペース分析 → 要件収集 →
ユーザーストーリー作成 → デザインビジョン（UIがある場合） →
アーキテクチャ設計 → GitHub issue生成。

全てのやり取りはチャットで行う。ドキュメントはユーザーの承認後に生成する。

## 実行方法

まず `.kiro/skills/inception/SKILL.md` を読み、各ステージの進行に合わせて
参照ファイルを読み込む。

## ステージ1: ワークスペース検出（常に実行）

1. inceptionスキルの `references/workspace-detection.md` を読む
2. ワークスペースをスキャン
3. `aidlc-docs/aidlc-state.md` を作成
4. チャットで検出結果を報告し、ステージ2へ進む

## ステージ2: 要件分析（常に実行）

1. `references/requirements-analysis.md` と `references/depth-levels.md` を読む
2. ユーザーのリクエストを分析
3. チャットで明確化のための質問を行う（選択肢形式）
4. 回答を集めた後、チャットで要件サマリーを提示
5. **ユーザーの承認を待ってから次へ進む**
6. `aidlc-docs/inception/requirements/requirements.md` を生成
7. `aidlc-docs/audit.md` に追記

## ステージ3: ユーザーストーリー（条件付き）

1. `references/user-stories.md` を読む
2. ストーリーが価値を持つか評価（スキップ条件を参照）
3. 実行する場合: チャットでペルソナとストーリーを提示
4. **ユーザーの承認を待つ**
5. 承認後にドキュメントを生成

## ステージ4: デザインビジョン（条件付き — UIがある場合）

1. `references/design-vision.md` を読む
2. プロダクトがUIを持つか評価（スキップ条件を参照）
3. 実行する場合: チャットでデザイン方針を質問（トーン、参考プロダクト、
   カラー、情報密度、デバイス、タイポ、モーション、A11y、UIキット、
   ブランドアセット）
4. **ユーザーが承認するまで議論・改善を繰り返す**
5. 承認後に `aidlc-docs/inception/design/design-vision.md` を生成
6. 決定したデザイン方針は次のアーキテクチャ設計で技術スタック選定の
   優先制約として引き継ぐ

## ステージ5: アーキテクチャ設計（条件付き）

1. `references/architecture-design.md` を読む
2. アーキテクチャ設計が必要か評価
3. 実行する場合: チャットでASCII図を使ってアーキテクチャを提案
   （ステージ4のデザインビジョンがあれば、UIキット・CSS戦略・
   コンポーネントライブラリはそれに従う）
4. **ユーザーが承認するまで議論・改善を繰り返す**
5. 承認後にドキュメントを生成

## ステージ6: 設計成果物レビュー（条件付き — DB/API/UIがある場合）

1. 以下の参照ファイルを順に読み、該当する成果物を作成する:
   - `references/db-design.md` — DB設計（DBML + HTML ER図）
   - `references/api-design.md` — API設計（REST→Swagger UI / GraphQL→Playground / gRPC→Proto docs）
   - `references/ui-design.md` — UI設計（HTML/CSS モックアップ）
2. **各成果物ごとにユーザーの承認を得る**（まとめて出さない）
3. 承認順序: DB → API → UI（後の設計が前の設計に依存するため）

### 承認基準
- ユーザーが「OK」「承認」「進めて」等の明示的な承認を出すまで次に進まない
- 部分承認（「DBはOKだがAPIは修正して」）も受け付ける
- 全成果物が承認されたらステージ7へ
- **設計が未承認の状態で機能実装のissueを生成してはならない**
  （Phase 0: scaffold/CI/infraのissueは設計承認前でも生成OK）

## ステージ7: Issue生成（常に実行）

1. `references/issue-generation.md` を読む
2. これまでのINCEPTION成果物を全て読む
3. 実装可能・独立・テスト可能なissueに分解
4. チャットでissueリストをユーザーに提示し最終確認
5. `gh issue create` でissueを作成
6. `.kiro/steering/development-rules.md` に確定した技術スタックを記入
7. INCEPTION ドキュメントをコミットしてpush（`issue/task.md` はローカル
   保持なので含めない）:
   ```bash
   git add aidlc-docs/ .kiro/steering/
   git commit -m "docs: add INCEPTION artifacts"
   git push --no-verify origin HEAD
   ```
8. ユーザーに `/quit` と入力してパイプラインを自動起動するよう伝える

## ルール

- 全てのやり取りはチャットで行う — 質問ファイルは使わない
- 日本語で応答する
- 各ステージの決定を `aidlc-docs/audit.md` にISO 8601タイムスタンプ付きで追記
- ステージ2, 3, 4ではドキュメント生成前にユーザーの承認が必要
- ドキュメントはチャットでの承認後にのみ作成
- 複雑さに応じて深度を調整（minimal / standard / comprehensive）
