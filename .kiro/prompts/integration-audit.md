---
name: integration-audit
description: develop ブランチの最新状態でアプリが統合的に動作するかを検証する。
---
# Integration Audit（統合監査）

develop ブランチの最新状態で「アプリ全体として動くか」を検証する。
個別PRのCIでは検出できない統合レベルの問題を発見し、修正issueを作成する。

## いつ実行されるか

- オーケストレーターが Phase 2 の実装PRが5件以上マージされた時点で自動起動
- オペレーターからの手動指示

## 検証手順

### 1. develop ブランチをチェックアウト

```bash
git checkout "${KIRO_INTEGRATION_BRANCH:-develop}"
git pull origin "${KIRO_INTEGRATION_BRANCH:-develop}"
```

### 2. ビルド検証

```bash
pnpm install
pnpm build
```

ビルドが通らない場合、エラーを分析して修正issueを作成。

### 3. エントリポイント接続確認

以下を確認する：

- **ルーティング**: フロントエンドのルーター（App.tsx等）に全ての実装済みページが登録されているか
- **API接続**: フロントエンドのAPI呼び出しURLとバックエンドのルート定義が一致しているか
- **認証フロー**: ログイン→トークン保存→API呼び出しにトークン付与の一連が繋がっているか
- **CORS/Proxy**: フロントエンドからAPIへのリクエストがブロックされないか（proxy設定 or CORS middleware）
- **DB接続**: in-memory stub が残っていないか、実際のDB接続が設定されているか
- **環境変数**: 必要な環境変数が.env.exampleに定義され、コード内で参照されているか

### 4. 起動検証

```bash
# dev server を起動して基本動作確認
just dev &
sleep 10
# ヘルスチェック
curl -s http://localhost:3000/health || echo "API not responding"
curl -s http://localhost:5173/ || echo "Web not responding"
kill %1
```

### 5. 問題発見時

発見した問題ごとにGitHub issueを作成する：

```bash
gh issue create \
  --title "fix(integration): <問題の要約>" \
  --label "P0-critical" --label "bug" \
  --body "## 問題
<何が壊れているか>

## 原因
<なぜ壊れているか — どのPRで見落とされたか>

## 修正方針
<具体的に何をすれば直るか>

## 影響範囲
<この問題が放置されると何が動かないか>"
```

### 6. 優先度判定

| 問題の種類 | 優先度 | 理由 |
|-----------|--------|------|
| ルーティング未接続 | P0-critical | ページが表示されない |
| API URL不一致 | P0-critical | 機能が動かない |
| 認証トークン未伝播 | P0-critical | ログイン後も未認証 |
| CORS/Proxy未設定 | P0-critical | ブラウザからAPI呼べない |
| in-memory stub残存 | P1-high | データが永続化されない |
| 環境変数未定義 | P1-high | デプロイ時にクラッシュ |
| 重複実装 | P2-medium | 保守性の問題 |
| バリデーション不足 | P2-medium | 異常系で500 |

## アンチパターン

- ❌ 個別ファイルの品質だけ見る（それはreview agentの仕事）
- ❌ 問題を見つけても自分で直す（issueを作ってimplement agentに任せる）
- ❌ テストの網羅性だけ見る（「動くか」が最優先）
