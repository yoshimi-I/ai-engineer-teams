# Launch Kit

## Positioning

`ai-engineer-teams` is a loop engineering runtime for GitHub issue-driven AI
coding teams.

It turns this:

```text
Human prompts agent -> agent edits code -> human checks PR -> human prompts again
```

into this:

```text
GitHub issue -> orchestrator -> Codex/Claude/Kiro pane -> PR -> CI/review -> next loop
```

## Short Description

Loop engineering runtime for autonomous AI coding teams: GitHub Issues become
the queue, zellij panes become workers, and Codex, Claude Code, or Kiro closes
the issue-to-PR-to-review loop.

## X / Twitter

```text
I built ai-engineer-teams: a loop engineering runtime for GitHub issue-driven AI coding teams.

GitHub Issues -> zellij workers -> Codex/Claude/Kiro -> PR -> CI/review -> next loop.

It is not "N agents forever"; it starts minimal and spawns only the role needed next.

https://github.com/yoshimi-I/ai-engineer-teams
```

## Hacker News

```text
Show HN: ai-engineer-teams, a loop engineering runtime for AI coding agents

I built a small shell/zellij/GitHub control plane that turns GitHub issues into
an autonomous coding loop. It watches issues, PRs, review decisions, CI, and
merge state, then spawns role-specific agent panes only when needed.

It supports Codex CLI, Claude Code, and Kiro CLI through AI_RUNNER.
```

## Reddit

```text
I made a loop engineering runtime for coding agents.

Instead of manually prompting an agent after every step, GitHub issues become
the queue and a zellij orchestrator spawns implement/review/fix/E2E panes as
the repo state changes. It supports Codex CLI, Claude Code, and Kiro CLI.
```

## Zenn / Qiita Title Ideas

- GitHub issue を AI agent team の work queue にする loop engineering runtime を作った
- Codex / Claude Code / Kiro を zellij で動的に束ねる agent loop 実装
- 「agent に毎回 prompt する」をやめて、prompt する仕組みを作る

## GitHub Metadata

Description:

```text
Loop engineering runtime for GitHub issue-driven AI coding teams: Codex, Claude Code, Kiro, zellij.
```

Topics:

```text
loop-engineering, ai-agents, coding-agents, codex, codex-cli, claude-code, kiro, zellij, github-automation, agentic-workflow
```
