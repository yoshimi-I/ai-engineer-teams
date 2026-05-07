# Delivery Pipeline — コードからユーザーが使える状態まで

## いつ使うか

- INCEPTION でissueを生成する時
- implement エージェントが「完了」を判断する時
- review エージェントがマージ可否を判断する時

## 原則

**「PRがマージされた」≠「完了」。ユーザーがアクセスできて初めて完了。**

## 完了の定義 (Definition of Done)

機能が「完了」と見なされるには、以下の全てを満たす必要がある:

1. ✅ コードが実装されている
2. ✅ テストが書かれ、通っている
3. ✅ CIが通っている（lint, typecheck, test, build）
4. ✅ レビューが承認されている
5. ✅ mainにマージされている
6. ✅ デプロイパイプラインが存在し、マージ後に自動デプロイされる
7. ✅ デプロイ先の環境でアクセス可能である

## 開発フロー全体像

```
INCEPTION
  ↓
Phase 0: 基盤構築（2トラック並行）
  ├── トラックA: アプリ基盤
  │   ├── scaffold (frontend / backend / shared)
  │   ├── justfile with dev recipe
  │   ├── CI パイプライン (lint + typecheck + test + build)
  │   └── .env.example + config loader
  ├── トラックB: インフラ・デプロイ基盤（即着手）
  │   ├── GitHub OIDC for AWS
  │   ├── VPC + networking (Terraform)
  │   ├── Database (RDS/Aurora)
  │   ├── Compute (ECS/Lambda)
  │   ├── ALB + DNS
  │   ├── Dockerfile (scaffold完了後)
  │   ├── Docker build + ECR push (CI)
  │   └── Staging deploy workflow
  └── 合流: トラックA の Dockerfile + トラックB のインフラ → CD 完成
  ↓
Phase 1: Walking Skeleton
  ├── /health エンドポイント → staging デプロイ → E2E
  └── ここで「コード→デプロイ」の全経路が開通
  ↓
Phase 2: 機能実装（デプロイ経路は既に開通済み）
  ├── ドメインモデル / スキーマ
  ├── API エンドポイント
  ├── フロントエンド UI
  └── 統合テスト / E2E
  ↓
Phase 3: デリバリー
  ├── production IaC + deploy
  └── ユーザーアクセス確認
```

### なぜインフラを最初から並行するか

Terraform は初回 `apply` で高確率でエラーが出る:
- IAM ポリシー不足
- リソースクォータ制限
- リージョン固有の制約
- ネットワーク設定ミス

機能実装が終わってからインフラに着手すると、ここで詰まって全体が止まる。
**最初から並行して走らせ、エラーを早期に潰す**のが正しい戦略。

## Phase 0 で生成すべきissue（INCEPTIONで必須）

### トラックA: CI（Continuous Integration）

| issue | 内容 | 依存 |
|-------|------|------|
| `ci: add linter and formatter` | oxlint/biome/eslint + CI ワークフロー | scaffold 後 |
| `ci: add typecheck and test` | tsc --noEmit + vitest/jest + CI ジョブ | linter 後 |
| `ci: add build verification` | pnpm build が通ることを CI で検証 | typecheck 後 |

### トラックB: インフラ（IaC）— scaffold を待たず即着手

| issue | 内容 | 依存 |
|-------|------|------|
| `infra: configure GitHub OIDC` | GitHub Actions → AWS の認証設定 | **なし（最初に作る）** |
| `infra: provision VPC + networking` | VPC/Subnet/SG | **なし** |
| `infra: provision database` | RDS/Aurora + セキュリティグループ | VPC 後 |
| `infra: provision compute` | ECS/Lambda + タスク定義 | VPC 後 |
| `infra: provision ALB + DNS` | ALB/CloudFront/Route53 | compute 後 |
| `infra: configure secrets` | Secrets Manager / SSM Parameter Store | **なし** |

### トラックB → CD（Continuous Deployment）— インフラ完成後

| issue | 内容 | 依存 |
|-------|------|------|
| `ci: add Docker build + ECR push` | Dockerfile + ECR push | scaffold + build verification 後 |
| `ci: add staging deploy` | main マージ → staging 自動デプロイ | Docker + OIDC + compute 後 |
| `ci: add production deploy` | タグ or 手動承認 → production デプロイ | staging deploy 後 |

### 環境構築

| issue | 内容 | 依存 |
|-------|------|------|
| `chore: add .env.example` | 全パッケージの環境変数テンプレート | scaffold 後 |

## Phase 2 の issue（既存のissue生成ルールに従う）

従来通り: scaffold → domain → API → UI → integration → E2E

## Phase 3 で生成すべきissue

| issue | 内容 | 依存 |
|-------|------|------|
| `chore: verify staging deployment` | staging 環境でのスモークテスト | CD + 機能実装完了後 |
| `chore: verify production deployment` | production 環境での動作確認 | staging 検証後 |

## issue 生成順序（INCEPTION での推奨順）

1. scaffold（フロント/バック/共有）
2. **CI: linter + formatter**
3. **CI: typecheck + test**
4. **CI: build verification**
5. ドメインモデル / DB スキーマ
6. **インフラ: compute + DB + networking**
7. **環境構築: .env.example, OIDC**
8. API エンドポイント
9. フロントエンド UI
10. **CI: Docker build + ECR push**
11. **CD: staging 自動デプロイ**
12. 統合 / E2E テスト
13. **staging 動作確認**
14. **CD: production デプロイ**
15. **production 動作確認**

## エージェントへの影響

| エージェント | 変更点 |
|------------|--------|
| implement | CI/infra/CD の issue も実装対象。IaC スキルを参照 |
| review | CI が通っていない PR はマージしない。デプロイ issue の PR は plan 結果を確認 |
| orchestrator | Phase 1 の issue を Phase 2 より先に消化するよう優先 |
