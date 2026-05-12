---
name: to-japanese
description: プロジェクトのドキュメントとプロンプトを日本語化する。
---
# 日本語化

`.kiro/prompts/` 内の全プロンプトと `.kiro/steering/` 内の全steeringファイルを日本語に翻訳する。

## ルール

- SKILL.md（`.kiro/skills/`）は翻訳しない（英語のまま）
- frontmatter（`---` で囲まれた部分）は翻訳しない
- コマンド例（`bash` コードブロック内）は翻訳しない
- テーブルのヘッダーと内容は翻訳する
- ファイル名は変更しない
- 1ファイルずつ読み→翻訳→書き込みを行う
