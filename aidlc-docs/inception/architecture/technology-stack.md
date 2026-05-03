# Technology Stack

## Application

| Layer | Technology |
|-------|-----------|
| Chrome Extension | Manifest V3, TypeScript |
| Web App | Vite + React + TypeScript (Bulletproof React) |
| Backend API | Hono (TypeScript) on ECS Fargate (Clean Architecture + Hexagonal) |
| Auth | Amazon Cognito |
| Database | Amazon RDS (PostgreSQL) |
| Load Balancer | ALB |
| CDN + Hosting | S3 + CloudFront |
| Infrastructure | Terraform |

## Toolchain

| Purpose | Tool |
|---------|------|
| Format | oxc (oxc_formatter) |
| Lint | oxlint |
| Type check | tsgo |
| Test | Vitest + similar-ts |
| Dead code detection | knip |

## Architecture Patterns

| Component | Pattern |
|-----------|---------|
| api/ | Clean Architecture + DDD + Hexagonal |
| web/ | Bulletproof React (feature-based colocation) |
| extension/ | Content script + Service worker + Popup |
