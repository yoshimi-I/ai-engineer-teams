# Architecture

## System Overview

```
┌─────────────────────────────────────────────────────────┐
│                        AWS Cloud                         │
│                                                          │
│  ┌──────────┐    ┌─────────────────────────────────┐    │
│  │ Cognito  │    │         VPC                      │    │
│  │ User Pool│    │                                  │    │
│  └────┬─────┘    │  ┌───────┐    ┌──────────────┐  │    │
│       │          │  │  ALB  │───▶│ ECS Fargate  │  │    │
│       │          │  └───────┘    │  (Hono API)  │  │    │
│       │          │               └──────┬───────┘  │    │
│       │          │                      │          │    │
│       │          │               ┌──────▼───────┐  │    │
│       │          │               │ RDS Postgres  │  │    │
│       │          │               └──────────────┘  │    │
│       │          └─────────────────────────────────┘    │
│       │                                                  │
│  ┌────▼──────────────────┐                              │
│  │ S3 + CloudFront       │                              │
│  │ (Web App hosting)     │                              │
│  └───────────────────────┘                              │
└─────────────────────────────────────────────────────────┘

┌──────────────┐         ┌──────────────────┐
│ Chrome Ext   │────────▶│ ALB (Hono API)   │
│ (Manifest V3)│  REST   │                  │
└──────┬───────┘         └──────────────────┘
       │ DOM
       ▼
┌──────────────┐
│ Netflix /    │
│ YouTube      │
└──────────────┘
```

## Components

| Component | Responsibility |
|-----------|---------------|
| Chrome Extension | Subtitle DOM capture, word popup, shadowing control, API communication |
| Web App (SPA) | Vocabulary browsing, quiz, review management UI. Hosted on S3+CloudFront |
| Hono API (Fargate) | REST API. Auth verification, word CRUD, quiz generation, spaced repetition |
| RDS PostgreSQL | Persist users, words, review schedules, quiz results |
| Cognito | User authentication and token issuance. Shared by extension and web app |
| S3 + CloudFront | Static file delivery for web app |

## Communication

- Chrome Extension → Hono API: REST (JSON) + Cognito JWT
- Web App → Hono API: REST (JSON) + Cognito JWT
- Chrome Extension → External Dictionary API: REST (word meaning lookup)

## Clean Architecture (api/)

```
presentation → application → domain
                    ↑
              infrastructure
```

- `domain/`: Entities, value objects, repository interfaces. No external dependencies.
- `application/`: Use cases. Depends on domain interfaces.
- `infrastructure/`: Repository implementations (PostgreSQL), external APIs. Implements domain interfaces.
- `presentation/`: Hono routes. Calls application layer.

## DB Schema Overview

```
users          ─┐
                 ├──< words (user_id, word, meaning, context, source_url, created_at)
                 ├──< review_schedules (word_id, next_review_at, interval, ease_factor)
                 └──< quiz_results (word_id, is_correct, answered_at)
```

## Ports

| Service | Port |
|---------|------|
| Hono API (dev) | 3000 |
| Vite dev server | 5173 |
