# Dev Server — 開発サーバー常駐

`just dev` を実行して開発サーバー（フロントエンド + バックエンド）を起動・常駐させる。
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
just dev
```

`just dev` が存在しない場合は、プロジェクトの起動方法を自分で判断して起動する:
- `pyproject.toml` があれば: `uv run uvicorn app.main:app --host 0.0.0.0 --port 8000 --reload`
- `package.json` があれば: `pnpm dev` or `npm run dev`

## サーバーが落ちた場合

- 同じエラーで3回以上落ちた場合は、エラーの原因を調査して修正を試みる（`.env` 不足、ポート競合、依存不足等）
- 修正できない場合はエラー内容をログに残して停止する。無限再起動ループしない

## 禁止事項

- サーバー以外の作業（コード修正、issue作成等）は一切行わない
- サーバーを停止して別のことをしない
