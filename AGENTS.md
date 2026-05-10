# AI Engineer Teams

Auto-scaling agent development pipeline with AI-DLC INCEPTION planning.
The orchestrator starts minimal and spawns additional zellij panes on
demand based on open issues, PRs, and post-merge state — it is **not** a
fixed "N agent" pool.

This file is also loaded by Claude Code (via the `CLAUDE.md` symlink), so
the same project rules apply whether the pipeline is driven by Kiro CLI
(`KIRO_AI_RUNNER=kiro`, default) or Claude Code (`KIRO_AI_RUNNER=claude`).
Slash commands live in `.kiro/prompts/` and are mirrored at
`.claude/commands/`; skills live in `.kiro/skills/` and are mirrored at
`.claude/skills/`.

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
- Parallel agents: assignee-based mutex on GitHub issues is the source of
  truth. `issue/task.md` is an auxiliary local log.
- Audit trail: all decisions recorded in `aidlc-docs/audit.md`

## After INCEPTION

Run `./scripts/start-pipeline.sh` (or `just start`) to launch the
orchestrator in zellij. The orchestrator:

- Starts minimal (no agent panes)
- Adds `implement` panes when ready issues appear (AI planner decides count)
- Adds `review` panes when APPROVED PRs need merge-manager handling
- Adds `fix-review` panes when review changes / conflicts need fixing
- Adds `e2e-hunt` / `ui-audit` / `watch-main` panes based on merge state
  and env-var flags (`ORCH_AUTO_*`)

See [README.md](README.md) for the full architecture and env-var reference.
