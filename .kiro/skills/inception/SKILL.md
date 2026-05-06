---
name: inception
description: >
  AI-DLC INCEPTIONフェーズ: 構造化されたプロジェクト計画ワークフロー。
  ワークスペース検出、要件分析、ユーザーストーリー、アーキテクチャ設計、issue生成。
  新規プロジェクト開始、機能計画、既存コードベース分析時に使用。
  トリガー: 新規プロジェクト, 計画, 要件, アーキテクチャ, 設計, ブレスト, inception。
---

# INCEPTIONフェーズ — 適応型プロジェクト計画

AI-DLCから適応した構造化計画ワークフロー。
要件 → 設計 → issue生成をプロジェクトの複雑さに応じて適応的にガイドする。

## ワークフロー

```
1. ワークスペース検出（常に実行）
2. 要件分析（常に実行、適応的深度）
3. ユーザーストーリー（条件付き）
4. デザインビジョン（条件付き — UIがある場合）
5. アーキテクチャ設計（条件付き）
6. Issue生成（常に実行）→ オーケストレーターに供給
```

## 詳細ステップは `references/` にあり、必要に応じて読む:

- `references/workspace-detection.md`
- `references/requirements-analysis.md`
- `references/user-stories.md`
- `references/design-vision.md`
- `references/architecture-design.md`
- `references/issue-generation.md`
- `references/depth-levels.md`
- `references/question-format.md`
