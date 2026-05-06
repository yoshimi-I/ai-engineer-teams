# アーキテクチャ設計（条件付き）

## 実行条件
- 新しいコンポーネントやサービスが必要
- システムアーキテクチャの決定が必要
- 複数のサービスやモジュール
- インフラ設計が必要

## スキップ条件
- 既存コンポーネント境界内の変更
- 既存アーキテクチャへのシンプルな機能追加

## ステップ

### 1. コンテキストを分析
要件とユーザーストーリー（生成済みの場合）を読む。
デザインビジョン（`aidlc-docs/inception/design/design-vision.md`）が
生成済みの場合は必ず読み、UIキット・CSS戦略・コンポーネントライブラリ・
モーションライブラリ選定はそこで合意した方針に従う。

### 2. チャットでアーキテクチャを提案
ユーザーに提示:
- 主要コンポーネントと責務
- 通信パターン（REST、WebSocket、イベント）
- 技術スタックの推奨と根拠
- ディレクトリ構成

チャットでシンプルなASCII図を使用:
```
[フロントエンド] → [APIサーバー] → [データベース]
                      ↓
                 [WebSocket]
```

### 3. 議論と改善
ユーザーにフィードバックを求める。承認されるまで反復。

### 4. ドキュメントを生成
承認後、`aidlc-docs/inception/architecture/` に作成:
- `architecture.md`
- `technology-stack.md`
- `directory-structure.md`

### 5. justfile にサーバー起動コマンドを追加（必須）

アーキテクチャ確定後、`justfile` に以下のレシピを追加する。これは後続の全エージェント（Watch-Main, E2E-Hunt等）がサーバー起動に使用する。

追加するレシピ:

```just
# Start all dev servers in background
dev:
    #!/usr/bin/env bash
    # 既存プロセスを停止
    lsof -ti:{バックエンドポート} 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    lsof -ti:{フロントエンドポート} 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    sleep 1
    # バックエンド起動
    cd {バックエンドディレクトリ} && nohup {バックエンド起動コマンド} > /tmp/dev-backend.log 2>&1 &
    # フロントエンド起動
    cd {フロントエンドディレクトリ} && nohup {フロントエンド起動コマンド} > /tmp/dev-frontend.log 2>&1 &
    # ready待機
    for i in $(seq 1 30); do
      if lsof -ti:{バックエンドポート} > /dev/null 2>&1 && lsof -ti:{フロントエンドポート} > /dev/null 2>&1; then
        echo "✅ All servers ready"; exit 0
      fi
      sleep 2
    done
    echo "⚠️ Timeout"; exit 1

# Stop all dev servers
dev-stop:
    lsof -ti:{バックエンドポート} 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    lsof -ti:{フロントエンドポート} 2>/dev/null | xargs -r kill -9 2>/dev/null || true
    @echo "✅ Servers stopped"
```

`{バックエンドポート}`, `{フロントエンドポート}`, `{起動コマンド}` はアーキテクチャで決定した内容に置き換える。

**重要**: `just dev` が正常に動作することを実際に実行して確認すること。動かない場合はその場で修正する。
