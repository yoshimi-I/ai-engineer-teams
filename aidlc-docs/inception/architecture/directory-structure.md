# Directory Structure

```
netflix-english-study/
├── extension/                  # Chrome Extension (Manifest V3)
│   ├── src/
│   │   ├── content/            # Content script (subtitle capture, UI injection)
│   │   ├── background/         # Service worker
│   │   ├── popup/              # Extension popup UI
│   │   └── shared/             # Shared types and utilities
│   ├── manifest.json
│   ├── package.json
│   └── tsconfig.json
├── web/                        # Web App (Vite + React, Bulletproof React)
│   ├── src/
│   │   ├── app/                # App init, routing, providers
│   │   ├── features/           # Feature-based colocation
│   │   │   ├── auth/
│   │   │   │   ├── components/
│   │   │   │   ├── hooks/
│   │   │   │   ├── api/
│   │   │   │   ├── types/
│   │   │   │   └── index.ts
│   │   │   ├── vocabulary/
│   │   │   ├── quiz/
│   │   │   └── review/
│   │   └── shared/             # Shared components, hooks, utils
│   ├── package.json
│   └── vite.config.ts
├── api/                        # Hono API (Clean Architecture + Hexagonal)
│   ├── src/
│   │   ├── domain/             # Entities, value objects, repository interfaces
│   │   │   ├── word/
│   │   │   ├── review/
│   │   │   └── quiz/
│   │   ├── application/        # Use cases
│   │   │   ├── word/
│   │   │   ├── review/
│   │   │   └── quiz/
│   │   ├── infrastructure/     # DB implementations, external APIs, Cognito
│   │   │   ├── persistence/
│   │   │   ├── auth/
│   │   │   └── dictionary/
│   │   ├── presentation/       # Hono routes, middleware
│   │   │   ├── routes/
│   │   │   └── middleware/
│   │   └── index.ts
│   ├── Dockerfile
│   ├── package.json
│   └── tsconfig.json
├── infra/                      # Terraform
│   ├── modules/
│   │   ├── vpc/
│   │   ├── ecs/
│   │   ├── rds/
│   │   ├── cognito/
│   │   ├── alb/
│   │   └── cdn/
│   ├── envs/
│   │   └── dev/
│   └── main.tf
├── scripts/                    # Pipeline scripts (existing)
├── aidlc-docs/                 # INCEPTION artifacts
└── justfile
```
