---
name: to-english
description: プロジェクトのドキュメントとプロンプトを英訳する。
---
# Translate to English

Translate all prompt files in `.kiro/prompts/` and all steering files in `.kiro/steering/` to English.

## Rules

- Do NOT translate SKILL.md files (`.kiro/skills/`) — keep as-is
- Do NOT translate frontmatter (between `---` markers)
- Do NOT translate command examples (inside `bash` code blocks)
- Translate table headers and content
- Do NOT rename files
- Process one file at a time: read → translate → write
