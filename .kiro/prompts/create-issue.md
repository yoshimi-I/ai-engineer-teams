---
name: create-issue
description: 小粒で依存関係が明確な GitHub issue を1本単位で作成する。
---
# Issue作成スキル — 小粒 + 依存明確な issue を 1 本単位で書く

## Philosophy

issue の質 = 実装速度 × 並列度。1 PR = 1 issue = 15 分で読めるレビュー。
数は多くて構わない。小粒 + 依存タイプ明記が常に正義。

詳細ルールは `.kiro/skills/inception/references/issue-generation.md` を参照。
この skill はその原則に沿って **日常の単発 issue 追加**を扱う。

## 粒度の目安 (超えるなら分割)

| 項目 | 目安 |
|------|------|
| 正味 LOC | 50〜300 行 (テスト除く) |
| 触るファイル | 1〜5 |
| 受け入れ基準 | 1〜3 項目 |
| レビュー時間 | 5〜15 分 |

## Process

### Step 1: 要望の明確化
- 何を実現したいか、なぜ必要か、スコープを整理
- 不明点は選択肢とメリデメを提示して質問。丸投げの質問は禁止
- 要望が大きそうなら **複数 issue に割る前提**でヒアリングする

### Step 2: コードベース徹底調査
最低 5 ファイル以上読んでから issue を書く:
1. 変更対象ファイル
2. 呼び出し元 / 依存先
3. 型定義・インターフェース
4. 既存の類似実装
5. テストファイル

### Step 3: 既存 issue 重複チェック + 依存特定
```bash
gh issue list --state open --limit 50 --json number,title,body
gh issue list --state closed --limit 30 --json number,title
```

- 既存 issue と同じファイルを触るなら **依存関係**として扱う
- 既存 issue を分解した方が良いと気づいたら、分解の提案を添える

### Step 4: 垂直スライスか水平基盤か判断

**垂直スライス**: DB → API → UI → テストを貫く機能単位。5〜10 issue に分解。
**水平基盤**: 複数機能の土台 (scaffold / 共通型 / CI / IaC)。単発 issue。

機能追加 = 垂直スライス優先。「ログイン追加」のような依頼は、create-issue で
1 枚書いて終わらせず、`issue-generation.md` の例A を参考に 5〜10 本に割る。

### Step 5: Issue 本文作成

実装者が読むだけで実装に入れるレベル。以下セクション必須:

```markdown
## 概要
<1〜3 行>

## 背景・動機
<なぜ必要か>

## スコープ
- ✅ 含む: <具体的にやること>
- ❌ 含まない: <別issueで扱うもの、触らないファイル>

## 変更対象
- <ファイルパス / ディレクトリ>
- (並列化のため、他issueと重複しない領域を明記)

## 受け入れ基準
- [ ] <テスト可能な条件 1>
- [ ] <テスト可能な条件 2>
- [ ] 関連テスト追加 (ユニット / 統合 / E2E のうち適切なもの)

## 依存関係
- blocked-by: #<番号> (<タイプ: contract / data / impl / infra / test>)
- blocks: #<番号> (参考。任意)

## 実装メモ
<関連アーキ決定、主な関数シグネチャ、気をつける点>
```

**依存タイプ**:
- `contract`: 相手が型 / API / DB スキーマを公開するのを待つ
- `data`: 相手が migration / seed を流すのを待つ
- `impl`: 相手の実装が動く状態を待つ (一番強い)
- `infra`: 相手が CI / CD / IaC / シークレットを用意するのを待つ
- `test`: 相手の E2E が通ることを待つ

### Step 6: ラベル選定・Issue 作成

```bash
gh issue create \
  --title "feat(<scope>): <簡潔な動詞>" \
  --label "優先度" \
  --label "P0-critical|P1-high|P2-medium|P3-low" \
  --label "type-contract|type-data|type-impl|type-infra|type-test" \
  --body-file /tmp/issue-body.md
```

依存がある場合:

```bash
gh issue edit <番号> --add-label blocked
```

### Step 7: 分解した場合は index issue を立てる (任意)

1 つの要望を 5〜10 本に割った場合、親 issue を立てて見通しを良くする:

```markdown
## 親 issue: feat(auth): Login feature tracking

このトラッカーの子 issue:
- [ ] #101 contract
- [ ] #102 users table
- [ ] #103 password hash
- [ ] #104 JWT util
- [ ] #105 POST /signup
...

## Walking Skeleton Gate
最低 #101, #102, #105, #107 が merge されれば signup フローが通る。
```

ラベルは `tracker` を付け、Impl エージェントが着手しないようにする。

## Rules

- 調査せずに issue を書かない。最低 5 ファイルは読む
- **粒度目安を超えそうなら必ず分割する**。issue 数が多くなるのは許容
- 変更方針のチェックリストは必ずファイルパス付き
- 依存関係を書くときは必ず**タイプを明記** (`blocked-by: #5 (contract)` のように)
- 変更対象が重なる issue は同時着手されないよう、後発 issue に `blocked` ラベル
- 1 つの大きな要望が来たら 1 issue で済ませず、垂直スライスに分解することを提案
- scaffold / CI / IaC のような水平基盤は独立 issue。まとめない
- E2E は実装 issue と**同じ Phase 内**で追加していく。リリース直前に 1 本で
  全部書く "E2E dump" issue は作らない
