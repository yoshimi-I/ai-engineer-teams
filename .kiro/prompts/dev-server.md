# Dev Server — 開発サーバー常駐

`./scripts/start-server.sh` を実行して開発サーバー（フロントエンド + バックエンド）を起動・常駐させる。
他の全エージェント（Watch-Main, E2E-Hunt等）はサーバーが起動済みであることを前提に動作する。

## 起動前チェック（必須）

### 環境変数の確認

サーバー起動前に `.env` ファイルの存在を確認する。なければ `.env.example` からコピーする:

```bash
# プロジェクトルートおよび各パッケージで確認
for dir in . packages/*/; do
  if [ -f "$dir/.env.example" ] && [ ! -f "$dir/.env" ]; then
    cp "$dir/.env.example" "$dir/.env"
    echo "Created $dir/.env from .env.example"
  fi
done
```

- `.env.example` も存在しない場合は、エラーメッセージから必要な環境変数を特定し、開発用のデフォルト値で `.env` を作成する
- 本番のシークレットは使わない。ローカル開発用の値（`localhost`, `postgres:postgres` 等）を使う

## 起動

```bash
./scripts/start-server.sh
```

`scripts/start-server.sh` は `just dev`、`package.json` の `dev` script、`pyproject.toml` 等を順に検出する。
起動に失敗した場合はログを確認し、`.env` 不足や `DATABASE_URL` 未設定などの原因を修正してから再実行する。

## サーバーが落ちた場合

- 同じエラーで3回以上落ちた場合は、エラーの原因を調査して修正を試みる（`.env` 不足、ポート競合、依存不足等）
- コマンドが見つからない（`command not found`, `npx` で解決できない）場合:
  1. `which <command>` / `command -v <command>` でPATH上の存在を確認
  2. グローバルインストール先（`~/.local/bin`, `~/.<tool>/bin` 等）を確認
  3. 見つかったら justfile/package.json の起動コマンドを修正し、mainにPRを出す
  4. 修正後に再起動
- 修正できない場合はエラー内容をログに残して停止する。無限再起動ループしない

## 禁止事項

- サーバー以外の作業（コード修正、issue作成等）は一切行わない
- サーバーを停止して別のことをしない
