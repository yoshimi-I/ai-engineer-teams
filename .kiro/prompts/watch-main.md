
# developブランチ監視・E2E検証・main昇格

ユーザーの指示を待たず、即座に `${KIRO_INTEGRATION_BRANCH:-develop}` ブランチの監視を開始する。develop へのマージをポーリングし、新しいマージを検出したらテスト実行 + ブラウザE2E検証 → バグ発見時はGitHub issueを作成。バグがなければ `${KIRO_STABLE_BRANCH:-main}` への昇格PRを作成し、チェック通過後に squash merge する。

## 絶対に守ること

- **ブラウザE2E検証をスキップしてはならない。静的検証だけで次のサイクルに進むことは禁止。**
- 各チェック項目を実際にブラウザツールで操作し、スクリーンショットで目視確認すること。
- バグを1つでも見つけたら、スクリーンショットを `/tmp/` に保存し、issue に添付する。

## 1サイクルの処理

1. `BASE_BRANCH="${KIRO_INTEGRATION_BRANCH:-develop}"` / `STABLE_BRANCH="${KIRO_STABLE_BRANCH:-main}"` を設定
2. `git fetch origin "$BASE_BRANCH" "$STABLE_BRANCH"` → 状態ファイル(`issue/watch-main-state.json`)と照合
3. 新コミットなし → 「監視継続中。」で2分待機→再チェック
4. 新コミットあり → マージされたPR特定 → `git reset --hard "origin/${BASE_BRANCH}"`
5. **静的検証**: steering ファイルから検証コマンドを確認して実行
6. **ブラウザE2E検証（絶対必須・スキップ厳禁）**: Dev-Serverが起動済みのサーバーを使い、主要動線を操作して確認
7. バグ発見 → `gh issue create --label "bug"` で1バグ=1issue作成（スクリーンショット必須）。main へ昇格しない
8. バグなし → `gh pr create --head "$BASE_BRANCH" --base "$STABLE_BRANCH"` で昇格PRを作成または既存PRを再利用し、`gh pr checks --watch` 通過後に `gh pr merge --squash`
9. 状態ファイル更新 → 2分待機 → 1に戻る

## バグ発見時の対応

1. スクリーンショットを `/tmp/bug-<簡潔な説明>.png` に保存
2. `gh issue create --label "bug"` で1バグ=1issue作成
   - 再現手順、期待される動作、実際の動作、スクリーンショットを含める

## よくあるミス

- **静的テストだけで済ませてブラウザを開かない → 最大の違反。絶対禁止。**
- **自分でサーバーを起動する → 禁止。Dev-Serverエージェントが別ペインで起動済み。**
- 全バグを1つのissueにまとめる → 1バグ = 1 issue
- デスクトップだけ見てモバイルを見ない → レスポンシブ検証必須
- スクリーンショットを撮らない → バグ報告にはスクリーンショット必須

## サーバーについて

Dev-Serverエージェントが別ペインでサーバーを起動済み。自分でサーバーを起動する必要はない。
サーバーが起動していない場合は「サーバーが起動していません」とだけ報告して次のサイクルを待つ。
