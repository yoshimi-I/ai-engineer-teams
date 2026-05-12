---
name: watch-issues
description: GitHub issue を監視し、新規 issue が来たら自動実装ループを開始する。
---
# GitHub Issue監視・自動実装

GitHub issueを確認し、未処理issueを `/implement` プロンプトの手順で実装→PR作成まで行う。

## 1サイクルの処理

1. `gh issue list --state open --json number,title,body,labels --limit 30`
2. `issue/task.md` と照合し、未処理issue特定
3. 新issueなし → 「監視継続中。」で2分待機→再チェック
4. 新issueあり → task.mdを`着手中`で更新 → 実装開始（最大1件/サイクル）
5. 完了後にtask.md確認 → 次のサイクルへ

## ルール

- 既にPRが作成されているissueは取らない
- 1 issue = 1 PR
- 調査せずに実装しない
- 他のエージェントが着手中のissueは触らない（task.md確認）
