# Issue生成（常に実行 — パイプラインへの引き渡し）

INCEPTION と自律パイプラインの橋渡し。設計ドキュメントを「1つの PR で閉じる
小粒な issue の依存グラフ」に変換する。

## コア原則

### 1. 小さい方がいい。多くても構わない

1 issue は 1 PR、1 PR は「**15 分で読めるレビュー**」の大きさを目安にする。

| 項目 | 目安 | 超えそうなら |
|------|------|-------------|
| 正味 LOC | 50〜300 行 (テスト除く) | 分割する |
| 触るファイル | 1〜5 | 分割する |
| 受け入れ基準 | 1〜3 項目 | 分割する |
| レビュー時間 | 5〜15 分 | 分割する |
| テスト追加 | ユニット + 統合 or E2E の組 | 足りないなら追加 issue |

**issue 数の上限は無い**。INCEPTION で 40 個、50 個になっても構わない。
「動くリリースにたどり着ける依存グラフ」を正しく描けることが重要。

数を気にして粗くまとめると、実装中のコンフリクト・レビュー疲弊・ロールバック困難
という後戻りコストが膨らむ。INCEPTION 時に小さく切っておく方が全体では速い。

### 2. Walking Skeleton を最初に通す

機能を横に広げる前に、**最小の end-to-end 貫通路を 1 本**完成させる。
ユーザーが触れる導線 (1つで良い) と、その基盤となる scaffold / CI / deploy
を先に全部作る。

Walking Skeleton が完成した時点で:
- ユーザーがアクセス可能 (staging でも可)
- CI が走って PR を自動レビュー/マージできる
- 最低 1 本の E2E が `main` まで昇格する経路がある

この骨格ができた後で、各画面・API を**垂直スライス**で順に厚くしていく。

### 3. 垂直スライスを優先、水平レイヤー分割は基盤だけ

**垂直スライス (推奨)**: DB → API → UI → テストまで縦に貫く小さな機能単位。
ユーザーから見える価値がはっきりするので、並列化しても統合不安が少ない。

**水平レイヤー分割 (許可)**: scaffold、共通型定義、認証基盤など、複数の
垂直スライスが依存する「土台」だけに限る。水平分割を使いすぎると
「全部揃うまで動かない」状態が長引く。

```
良い例 (垂直スライス × 水平基盤):
  [水平] scaffold frontend / scaffold backend / CI / DB migration runner
  [水平] auth contract (types only) / shared UI primitives
  [垂直] login (DB → API → UI → E2E) を 5〜7 issue に分解
  [垂直] user profile (DB → API → UI → E2E) を 5〜7 issue に分解
  [垂直] dashboard (DB → API → UI → E2E) を 5〜7 issue に分解
```

### 4. 依存関係はタイプで区別する

`depends-on` だけでは「何を待てば良いか」が曖昧。本文に **依存タイプ**を明記する:

| タイプ | 意味 | 例 |
|-------|------|-----|
| `contract` | 相手が型 / API スキーマ / DBスキーマを公開するのを待つ | API 実装は contract issue の merge 待ち |
| `data` | 相手が DB migration / seed を流すのを待つ | API 実装は schema migration 待ち |
| `impl` | 相手の実装が動く状態を待つ (一番強い依存) | UI 実装は API の動作確認済み待ち |
| `infra` | 相手がインフラ / CI / シークレットを用意するのを待つ | deploy issue は IaC 完成待ち |
| `test` | 相手の E2E が通ることを待つ (リリース前の最終関門) | promote は E2E 通過待ち |

同じ issue 番号でも依存タイプが違えば扱いが違う。タイプを書くと AI planner
が「contract だけ merge されれば並列に実装を始められる」と判断できる。

## ステップ

### 1. 全 INCEPTION アウトプットを読む

- `aidlc-docs/inception/requirements/requirements.md`
- `aidlc-docs/inception/user-stories/stories.md` (存在する場合)
- `aidlc-docs/inception/design/design-vision.md` (存在する場合)
- `aidlc-docs/inception/architecture/` (存在する場合)

### 2. Release Plan を組み立てる

`.kiro/skills/delivery-pipeline/SKILL.md` を必ず読んでから、以下のフェーズで
issue を配置する。**各フェーズ内でさらに小粒化**する。

#### Phase 0: Foundations (必ず作る / 水平)

Phase 0 は **2つの並行トラック** で進める。互いに依存しないため同時に着手可能。

**トラック A: アプリ基盤**
- `chore: scaffold frontend` (Vite/Next/等の初期化だけ)
- `chore: scaffold backend` (Hono/Express/FastAPI/等の初期化だけ)
- `chore: add justfile with dev recipe` (開発サーバー起動コマンドを定義 — dev-server エージェントが `just dev` で起動するため必須。Docker Compose 推奨: `just dev` → `docker compose up`)
- `chore: add CI workflow (lint + typecheck + test + build)`
- `chore: add .env.example and config loader`
- `chore: add database migration runner` (必要なら)

**トラック B: インフラ・デプロイ基盤（アプリ実装を待たず即着手）**
- `infra: configure GitHub OIDC for AWS` (依存なし — 最初に作る)
- `infra: provision VPC + networking` (依存なし)
- `infra: provision database` (VPC後)
- `infra: provision compute (ECS/Lambda)` (VPC後)
- `infra: provision ALB + DNS` (compute後)
- `chore: add dockerfile for frontend` (scaffold後)
- `chore: add dockerfile for backend` (scaffold後)
- `ci: add Docker build + ECR push` (dockerfile後)
- `ci: add staging deploy workflow` (OIDC + compute + Docker build 後)

**なぜ並行か**: Terraform は初回 apply でエラーが出やすい（IAM不足、リソース制限、
リージョン制約等）。機能実装が終わってからインフラに着手すると、ここで詰まって
全体が止まる。最初から並行して走らせ、エラーを早期に潰す。

```
時間軸 →
トラックA: [scaffold] → [CI] → [機能実装...]
トラックB: [OIDC+VPC] → [DB+Compute] → [ALB] → [Docker+CD] → [デプロイ検証]
                                                       ↑ ここでトラックAのDockerfileと合流
```

※ これらを 1 つの大きな "setup" にしない。scaffold と CI は独立、Docker と
IaC も独立。並列化できる。
※ **justfile の `dev` レシピは最初の scaffold issue に含めること。** dev-server エージェントは `just dev` を最優先で探すため、これがないとサーバーが起動できない。

#### Phase 1: Walking Skeleton (垂直、1本だけ)

最小の end-to-end を 1 本通す。例: `/health` エンドポイントが UI から叩けて、
staging で表示され、E2E が main 昇格する。

- `feat: add /health API endpoint (returns 200)`
- `feat: add /health UI page (fetches /health)`
- `test: add E2E that loads /health page and asserts 200`
- `chore: enable promote-main workflow with /health E2E as gate`

この 4 つが merge されたら「最初のリリース可能状態」。ここから先は機能追加。

#### Phase 2: Vertical Slices (垂直、各機能 5〜10 issue)

各機能を **contract → data → impl → UI → test** の順で小粒に分解。
例は下の「分割例」を参照。

#### Phase 3: Hardening (水平、既存を厚くする)

- `feat: add error states to <screen>`
- `feat: add empty states to <screen>`
- `feat: add loading skeletons to <screen>`
- `test: add E2E for <error path>`
- `chore: add rate limiting to <endpoint>`
- `perf: add caching to <query>`

#### Phase 4: Release Polish (水平、production を向くもの)

- `chore: add IaC for production`
- `chore: add production secrets via GitHub Environments`
- `chore: add sentry / observability for production`
- `docs: add README user-facing section`

### 3. 分割例

#### 例A: ログイン機能 (垂直スライス × 縦に薄く)

悪い例 (1 issue で全部):
```
feat: implement authentication  ← 粗すぎ
```

良い例 (10 issue に分解):

```
#101 feat(auth): add User domain model + Zod schema          [contract]
#102 feat(auth): add users table migration                   [data] depends-on #101 (contract)
#103 feat(auth): add password hashing util (argon2 wrapper)  [impl]
#104 feat(auth): add JWT sign/verify util                    [impl]
#105 feat(auth): add POST /signup endpoint                   [impl] depends-on #102 (data), #103 (impl)
#106 feat(auth): add POST /login endpoint                    [impl] depends-on #102 (data), #103 (impl), #104 (impl)
#107 feat(auth): add /signup UI form                         [impl] depends-on #105 (contract)
#108 feat(auth): add /login UI form                          [impl] depends-on #106 (contract)
#109 feat(auth): add session cookie middleware               [impl] depends-on #104 (impl)
#110 test(auth): E2E signup → login → access protected page  [test]  depends-on #107, #108, #109 (impl)
```

ポイント:
- `#101` は型定義だけ → `#102`, `#105`, `#106`, `#107`, `#108` が依存
- `#101` が merge されれば、フロントとバックが **contract 依存**で並列実装できる
- `#103` (ハッシュ) と `#104` (JWT) は独立 → 並列可能
- `#105` と `#106` は同じ user テーブルを使うが別エンドポイント → 並列可能
- `#107` と `#108` は別画面 → 並列可能
- `#109` (middleware) は `#104` が終われば走れる

#### 例B: ダッシュボード機能 (垂直スライス × ウィジェット単位)

```
#201 feat(dashboard): add Dashboard page shell (layout only)  [impl]
#202 feat(dashboard): add Revenue widget (stub data)          [impl] depends-on #201 (impl)
#203 feat(dashboard): add Revenue API endpoint                [impl] depends-on #102 (data)
#204 feat(dashboard): connect Revenue widget to API           [impl] depends-on #202, #203 (impl)
#205 feat(dashboard): add Traffic widget (stub data)          [impl] depends-on #201 (impl)
#206 feat(dashboard): add Traffic API endpoint                [impl]
#207 feat(dashboard): connect Traffic widget to API           [impl] depends-on #205, #206 (impl)
#208 test(dashboard): E2E loads and asserts widgets render    [test] depends-on #204, #207 (impl)
```

ポイント:
- `#201` の shell が先に入ると、`#202` と `#205` のウィジェットが並列実装できる
- ウィジェットごとに「stub データ → API → 接続」の 3 段階に分ける
- ウィジェット同士は**水平に並列**、各ウィジェット内は**垂直に順次**

#### 例C: CI/CD パイプライン (水平、基盤)

```
#301 chore(ci): add lint workflow                             [infra]
#302 chore(ci): add typecheck workflow                        [infra]
#303 chore(ci): add test workflow                             [infra]
#304 chore(ci): add build workflow                            [infra]
#305 chore(ci): require all 4 checks for develop merge        [infra] depends-on #301, #302, #303, #304 (infra)
#306 chore(ci): add docker build for frontend                 [infra] depends-on #304 (infra)
#307 chore(ci): add docker build for backend                  [infra] depends-on #304 (infra)
#308 chore(cd): add OIDC role for staging deploy              [infra]
#309 chore(cd): add staging deploy workflow                   [infra] depends-on #306, #307, #308 (infra)
#310 chore(cd): add promote-main workflow                     [infra] depends-on #309 (infra)
```

ポイント:
- CI の 4 ワークフロー (`#301`〜`#304`) は互いに独立 → 並列可能
- `#305` は「required checks」設定で全員待ち → 合流点
- Docker ビルドは `build` ワークフローに乗るので `#304` 依存
- OIDC (`#308`) と docker (`#306`, `#307`) は並列だが、`#309` で合流

### 4. 本文テンプレ (必須セクション)

```markdown
## 概要
<1〜3 行でこの issue が何を足すか>

## 背景・動機
<なぜ必要か、どの要件/ストーリーを満たすか>

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

## 参照
- 要件: aidlc-docs/inception/requirements/requirements.md#<section>
- アーキ: aidlc-docs/inception/architecture/<file>.md
```

### 5. ラベル

`--label "優先度"` と `--label "P0-critical|P1-high|P2-medium|P3-low"` は必須。
加えて依存タイプと Phase を明示するラベルを推奨:

| ラベル | 用途 |
|-------|------|
| `phase-0-foundations` | scaffold / CI / IaC |
| `phase-1-skeleton` | walking skeleton |
| `phase-2-feature` | 機能実装 |
| `phase-3-hardening` | error states / empty states / polish |
| `phase-4-release` | production 向け |
| `type-contract` | 型 / API スキーマ / DB スキーマのみ |
| `type-data` | migration / seed |
| `type-impl` | 通常の実装 |
| `type-infra` | CI / CD / IaC |
| `type-test` | E2E / 追加テスト |
| `blocked` | 依存待ち (依存先が merge されたら外す) |

### 6. 作成

```bash
gh issue create \
  --title "feat(auth): add User domain model + Zod schema" \
  --label "優先度" --label "P1-high" \
  --label "phase-2-feature" --label "type-contract" \
  --body-file /tmp/issue-101.md
```

依存がある issue は `blocked` ラベルを付ける:

```bash
gh issue edit <番号> --add-label blocked
```

依存先が merge されたら、github.sh の `auto_unblock_issues` が自動で外す。

### 7. 依存グラフを aidlc-docs に記録

`aidlc-docs/inception/issue-graph.md` を作成し、mermaid で依存グラフを描く:

```markdown
# Issue Dependency Graph

\`\`\`mermaid
graph LR
  101[#101 User domain<br/>contract] --> 102[#102 users table<br/>data]
  101 --> 107[#107 signup UI]
  101 --> 108[#108 login UI]
  102 --> 105[#105 POST /signup]
  102 --> 106[#106 POST /login]
  103[#103 password hash] --> 105
  103 --> 106
  104[#104 JWT util] --> 106
  104 --> 109[#109 session middleware]
  105 --> 107
  106 --> 108
  109 --> 110[#110 E2E]
  107 --> 110
  108 --> 110
\`\`\`
```

これがあると、後から join する開発者 / AI planner が並列化可能な issue
を一目で把握できる。

### 8. steering を更新

確定した技術スタックとプロジェクト規約を
`.kiro/steering/development-rules.md`「プロジェクト固有設定」に記入。

### 9. 状態を更新

`aidlc-docs/aidlc-state.md`:
```
- 現在のフェーズ: INCEPTION ✅ → CONSTRUCTION
- 作成issue数: <件数>
- Walking Skeleton target: #<番号>s
```

### 10. ユーザーに指示

`/quit` と入力してこのセッションを終了。パイプラインが自動起動する。

## アンチパターン

- ❌ `feat: implement authentication` (粗い、5〜10 issue に割る)
- ❌ `feat: frontend and backend for login` (垂直混在、レイヤー別に割る)
- ❌ 並列化できないほど細かい `feat: rename variable foo to bar` (こちらは逆に統合)
- ❌ 依存タイプを書かず `depends-on: #5` だけ (contract/impl が見分けられない)
- ❌ Phase 1 (walking skeleton) を飛ばして Phase 2 に突入 (デリバリー不能)
- ❌ scaffold を 1 つの巨大 issue にまとめる (並列化の機会を潰す)
- ❌ E2E をリリース直前に 1 issue で全部足す (実装と並行して E2E も厚くする)
