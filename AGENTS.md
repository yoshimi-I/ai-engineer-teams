# Kiro Engineer Teams

8-agent parallel development pipeline with AI-DLC INCEPTION planning.

## First interaction

Tell me what you want to build. The INCEPTION workflow starts automatically:
1. Workspace detection → analyze existing code (if any)
2. Requirements analysis → clarify what to build
3. User stories → define user-facing behavior (if needed)
4. Architecture design → choose tech stack and structure (if needed)
5. Issue generation → create GitHub issues for the pipeline

## Language

Always respond in Japanese.

## Rules

All rules are in `.kiro/steering/development-rules.md`. Key points:
- TDD: write tests before implementation
- 3-layer testing: unit + integration + E2E required
- Git: worktree isolation, Conventional Commits (English), squash merge
- PR comments and issues: always in English
- Parallel agents: check `issue/task.md` before starting work
- Audit trail: all decisions recorded in `aidlc-docs/audit.md`

## After INCEPTION

Run `./scripts/start-pipeline.sh` to launch 8-agent pipeline in zellij.
