# 30-Second Demo Script

Use this when recording a GIF, asciinema, or terminal video for the README,
X, Hacker News, Reddit, Zenn, or Qiita.

## Setup

```bash
git clone https://github.com/yoshimi-I/ai-engineer-teams.git loop-demo
cd loop-demo
just setup
AI_RUNNER=codex just preflight
```

For the cleanest recording, use a test repository with one small issue already
open, for example:

```text
feat: add a health check command
```

## Recording Flow

```bash
AI_RUNNER=codex just start
```

Capture these beats:

1. Preflight validates GitHub, zellij, runner, ShellCheck, and BATS.
2. INCEPTION or existing artifacts define the issue queue.
3. The orchestrator starts with minimal panes.
4. A ready GitHub issue appears.
5. An `implement` pane is spawned.
6. The agent opens a PR.
7. CI and review state feed back into the next loop.

## Suggested Voiceover

```text
This is ai-engineer-teams: a loop engineering runtime for GitHub issue-driven
AI coding teams. GitHub issues become the queue, zellij panes become workers,
and Codex, Claude Code, or Kiro performs the work. The orchestrator watches
issues, PRs, reviews, CI, and merge state, then prompts the right agent at the
right time.
```

## One-Screen Terminal Mock

```text
GitHub issue #42 ready
  -> orchestrator launches implement-1
  -> Codex works in a zellij pane
  -> PR #43 opened
  -> CI/review pass
  -> merge manager promotes the change
  -> E2E/watch-main closes the loop
```
