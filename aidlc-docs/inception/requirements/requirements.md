# Requirements — Netflix English Study

## Product Overview

Chrome extension + Web app for English learning through Netflix and YouTube.
Captures subtitles in real-time from video page DOM, enables word/phrase saving, quizzes, and shadowing practice.

## Target Users

English learners (public service, account required).

## Functional Requirements

### Chrome Extension (during video playback)

| ID | Feature | Description |
|----|---------|-------------|
| F1 | Real-time subtitle capture | Extract English subtitle text from Netflix/YouTube page DOM |
| F2 | Word/phrase saving | Click word/phrase in subtitle → popup with meaning → save |
| F3 | Shadowing practice | Auto-pause per subtitle sentence → user speaks → resume + A-B repeat |
| F4 | Cloud sync | Sync saved words/phrases to backend |

### Web App (review)

| ID | Feature | Description |
|----|---------|-------------|
| F5 | Vocabulary list | Browse saved words/phrases, click to reveal meaning |
| F6 | Quiz generator | Auto-generate quizzes from saved words (multiple choice, fill-in-the-blank) |
| F7 | Spaced repetition | Manage review timing with spaced repetition algorithm |
| F8 | Authentication | Amazon Cognito login and user management |

## Non-Functional Requirements

| Category | Requirement |
|----------|-------------|
| Performance | Subtitle capture and popup display < 100ms, no impact on video playback |
| Security | Cognito auth, ALB auth integration, input validation, parameterized queries |
| Scalability | ECS Fargate auto-scaling |
| Browser support | Chrome (Manifest V3) |
| Supported sites | Netflix, YouTube |

## Tech Stack

| Layer | Technology |
|-------|-----------|
| Chrome extension | Manifest V3, TypeScript |
| Web app frontend | Vite + React + TypeScript |
| Backend | Hono (TypeScript) on ECS Fargate |
| Auth | Amazon Cognito |
| Database | Amazon RDS (PostgreSQL) |
| API | ALB → Fargate |
| Infrastructure | Terraform |
| Dictionary | External dictionary API (word meaning lookup) |

## Out of Scope (v1)

- Mobile app
- Video sites other than Netflix/YouTube
- Speech recognition for shadowing scoring
- Shared vocabulary lists between users
