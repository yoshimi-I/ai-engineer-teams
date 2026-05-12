<div align="center">

# 🏭 ai-engineer-teams

**Auto-scaling agent development pipeline**
**powered by [Kiro CLI](https://kiro.dev/docs/cli/) × [zellij](https://zellij.dev/)**

issue → implementation → review → merge → E2E verification — fully automated.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Kiro CLI](https://img.shields.io/badge/Kiro_CLI-compatible-purple.svg)](https://kiro.dev/docs/cli/)
[![CI + Kiro Review](https://img.shields.io/badge/CI-Kiro_Review-green.svg)](.github/workflows/kiro-review.yml)

**English** · [日本語](docs/README.ja.md)

</div>

---

## Quick Start

**1. Create project directory and clone template**
```bash
mkdir <your-project>
cd <your-project>
git clone https://github.com/yoshimi-I/ai-engineer-teams.git .
```

**2. Install prerequisites**
```bash
just setup
```

**3. Start (repo creation → INCEPTION → orchestrated pipeline)**
```bash
just start
```

`just start` continues from existing INCEPTION artifacts when they are present.
Use `just restart` to clear local agent runtime state and restart from the first post-INCEPTION pipeline cycle.

---

## 📥 Add to Existing Project

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yoshimi-I/ai-engineer-teams/main/scripts/install.sh)
just setup && just start
```

---

## 🔄 Full Flow

```
just start (./scripts/start-pipeline.sh)
│
├── Step 0: Preflight
│   ├── Template repo detection → create new repo (swap origin)
│   └── KIRO_API_KEY setup (GitHub Secrets)
│
├── Phase 1: INCEPTION (you + AI)
│   ├── 1. Workspace detection
│   ├── 2. Requirements analysis
│   ├── 3. User stories
│   ├── 4. Architecture design
│   └── 5. Auto-generate issues → GitHub issues
│
└── Phase 2: Autonomous pipeline (zellij)
    │
    └── Orchestrator (starts minimal → scales as needed)
        │
        ├── Issue detected → add one `implement` pane (default)
        ├── Review changes requested → add `fix-review` pane
        ├── Merge detected → add `e2e-hunt` pane
        └── `watch-main` / `improve` → only when explicitly enabled via env vars
```

---

## 🖥️ Zellij Tabs

| Tab | Key | Content |
|-----|-----|---------|
| **Pipeline** | Prefix+1 | Orchestrator — starts minimal, adds panes as needed |
| **Control** | Prefix+2 | TUI control panel — status, stop/restart, logs, current work |
| **Kiro** | Prefix+3 | Interactive kiro-cli — use `/slash-commands` manually |

### Control Panel

```
  🎛️  K I R O   C O N T R O L   P A N E L  🎛️

  18:30:00  Total: 12  ▶ 3  ✕ 0  💤 5

  ┌─────┬──────────────────┬──────────────┬──────────────────────────┐
  │  #  │ Agent            │ State        │ Detail                   │
  ├─────┼──────────────────┼──────────────┼──────────────────────────┤
  │  1  │ 🖥️  Dev-Server    │ 🔄 running   │ cycle #12                │
  │  2  │ 🔨 Impl-1        │ 🔄 running   │ cycle #5                 │
  │  3  │ 🔍 Review-3      │ 😴 sleeping  │ next in 10s              │
  └─────┴──────────────────┴──────────────┴──────────────────────────┘

  ⌨️  Actions
  [s] Stop agent    [r] Restart agent    [a] Stop all
  [l] View log      [o] Orchestrator     [q] Quit panel

  📋 Current Work
  Issues (in progress):
    #42 feat: add user authentication ← Impl-1
  Pull Requests:
    #45 [APPROVED] feat: add login page ← Impl-3
```

---

## 🤖 CI Reviews (Kiro and Claude Code)

Two parallel review workflows ship out of the box. Either or both can run;
configure whichever runner you use (or both):

| Workflow | Action | Required secret |
|----------|--------|-----------------|
| `.github/workflows/kiro-review.yml`   | [konippi/kiro-cli-review-action](https://github.com/konippi/kiro-cli-review-action) | `KIRO_API_KEY` from [app.kiro.dev](https://app.kiro.dev) |
| `.github/workflows/claude-review.yml` | [anthropics/claude-code-action](https://github.com/anthropics/claude-code-action) | `ANTHROPIC_API_KEY` from [console.anthropic.com](https://console.anthropic.com) |

**Setup:**

```bash
# Whichever runners you plan to use:
gh secret set KIRO_API_KEY        # for kiro-review.yml
gh secret set ANTHROPIC_API_KEY   # for claude-review.yml
```

Both workflows trigger on `develop`-bound PRs and respond to on-demand
comments:

| Trigger | Kiro | Claude |
|---------|:-:|:-:|
| `develop` PR opened / updated | auto | auto |
| `/review` PR comment          | ✅   | —   |
| `@claude` PR comment          | —    | ✅  |
| `/claude-review` PR comment   | —    | ✅  |

> ⚠️ `GITHUB_TOKEN` must be passed via `env` for the kiro action.
> Without it, the GitHub MCP server fails to start and reviews won't be posted.

> ⚠️ Do not use `@kiro` as a trigger phrase — it sends a mention notification
> to an unrelated GitHub user. Use `/review` for the kiro workflow.

| Role | CI Reviews (Kiro / Claude) | Local Review Agent |
|------|:-:|:-:|
| Code review | ✅ | — |
| Merge approved PRs | — | ✅ |
| Dependabot PRs | — | ✅ |

---

## 🏗️ Architecture

```
GitHub Issue
    │
    ▼
Orchestrator (starts with 1 agent, scales as needed)
    │
    ├── implement-1 → pick issue → implement → PR
    │   (more added as issues grow: implement-2, 3, ...)
    │                                │
    │                    CI: kiro-cli-review-action (strict 6-point review)
    │                                │
    │                         ┌──────┴──────┐
    │                      🟢 APPROVE    🔴 REQUEST_CHANGES
    │                         │              │
    │                    CI: Auto Merge  fix-review agent
    │                                    fixes → re-push
    │                         │
    │                    develop merged
    │                         │
    ├── dev-server → started when project has package.json etc.
    ├── watch-main → added after first develop merge → E2E verification → promote to main
    ├── e2e-hunt → added after first merge → Playwright patrol
    ├── ui-audit → added after first merge → design quality audit
    └── improve → added after first merge → improvement issues
```

---

## 📋 Prerequisites

| Tool | Install | Required |
|------|---------|:---:|
| [Kiro CLI](https://kiro.dev/docs/cli/) | See [downloads](https://kiro.dev/downloads/) | ✅ (one of the two) |
| [Claude Code](https://docs.claude.com/en/docs/claude-code/quickstart) | `npm i -g @anthropic-ai/claude-code` | ✅ (one of the two) |
| [zellij](https://zellij.dev/) | `brew install zellij` | ✅ 0.44.1+ |
| [GitHub CLI](https://cli.github.com/) | `brew install gh` → `gh auth login` | ✅ |
| [gum](https://github.com/charmbracelet/gum) | `brew install gum` | ✅ (for control panel) |
| [jq](https://jqlang.github.io/jq/) | `brew install jq` | ✅ |
| [just](https://just.systems/) | `brew install just` | Optional |

The pipeline can be driven by either runner; pick one with the
`AI_RUNNER` environment variable (default `kiro`). The legacy
`KIRO_AI_RUNNER` name is still honoured.

```bash
# Default: Kiro CLI
just start

# Drive the same pipeline with Claude Code
AI_RUNNER=claude just start
```

### Environment variables

The pipeline uses `AI_*` names, with `KIRO_*` aliases retained for
backward compatibility:

| Canonical name | Legacy alias | Purpose |
|---|---|---|
| `AI_RUNNER` | `KIRO_AI_RUNNER` | `kiro` (default) or `claude` |
| `AI_INTEGRATION_BRANCH` | `KIRO_INTEGRATION_BRANCH` | feature PR target (default `develop`) |
| `AI_STABLE_BRANCH` | `KIRO_STABLE_BRANCH` | promotion target (default `main`) |
| `AI_E2E_COMMAND` | `KIRO_E2E_COMMAND` | command run by `watch-main` for E2E gating |
| `KIRO_API_KEY` | _(no alias)_ | required by `konippi/kiro-cli-review-action` — name is fixed by the upstream action |
| `ANTHROPIC_API_KEY` | _(no alias)_ | required by `anthropics/claude-code-action` |

### Slash commands and skills are mirrored

- `.kiro/prompts/` ←→ `.claude/commands/` (symlink)
- `.kiro/skills/`  ←→ `.claude/skills/`  (symlink)
- `AGENTS.md`      ←→ `CLAUDE.md`         (symlink)

so editing the canonical `.kiro/` copy keeps both runners in sync.

zellij **0.44.1 or newer is required**. The orchestrator depends on the newer CLI automation APIs: `list-panes --json`, pane IDs, `--tab-id`, and `--close-on-exit`. Older versions such as `0.43.1` cannot run the dynamic pane lifecycle correctly.

```bash
zellij --version
brew upgrade zellij
```

The orchestrator uses an AI planner prompt (`.kiro/prompts/orchestrator-plan.md`) by default. Bash gathers GitHub, PR, pane, project, and post-merge state, asks the planner for a JSON action plan, validates that JSON, then launches only the approved zellij panes. The planner decides which roles to run (`dev-server`, `implement`, `review`, `fix-review`, `e2e`, `e2e-bug-hunt`, `ui-audit`, `watch-main`, `improve`) and how many `implement` panes to run based on dependencies, likely file conflicts, active panes, and review/e2e needs. Issues labeled `blocked` or waiting on an open `depends-on: #N` dependency are not considered ready. If AI planning fails, Bash falls back to dependency-aware scaling.

Run `just preflight` to diagnose local tools, GitHub auth, branch setup, Actions permissions, review secrets, workflows, and E2E command detection before launching the pipeline.

`watch-main` now runs as a resident develop-to-main promotion monitor by default and can be disabled with `ORCH_AUTO_WATCH_MAIN=false`. It requires a real E2E command for promotion (`AI_E2E_COMMAND`, the legacy `KIRO_E2E_COMMAND`, `just e2e`, or `package.json` `e2e`). `ui-audit` auto-spawns by default after merges and can be disabled with `ORCH_AUTO_UI_AUDIT=false`. Optional `improve` auto-spawn can be enabled with `ORCH_AUTO_IMPROVE=true`. AI planning can be disabled with `ORCH_AI=false`.

Code review is delegated to `konippi/kiro-cli-review-action` on `develop` PRs. The local `review` pane is a merge-manager only: it handles already approved PRs, waits for checks, and retries squash merge. PRs are normalized into states such as `review_pending`, `approved_ready`, `approved_pending`, `changes_requested`, `conflict`, `approved_checks_failed`, and `merge_blocked` so the planner and dashboard reason from the same state machine.

The orchestrator pane refreshes on a fixed tick (`ORCH_TICK_INTERVAL`, default `10s`) and shows the last planner source, launched actions, skip reasons, and next tick timing. The same state is written to `.agent-status/orchestrator.json` and `.agent-status/.cache/orchestrator_decision.json`.

---

## 🛡️ Guardrails

| Category | Rules |
|----------|-------|
| **Git safety** | No direct push to main/develop. Feature PRs merge into develop; only E2E-verified develop is promoted to main. No `--force`. No `git branch -D`. Squash merge only. |
| **Editor prevention** | `GIT_EDITOR=true` + `git config --global core.editor true` (3-layer) |
| **Filesystem** | No operations above project root. No `cd ..` or `../` paths. |
| **Issue limits** | improve: 3/cycle, e2e-bug-hunt: 5/cycle, watch-main: 3/cycle, ui-audit: 3/cycle |
| **Close protection** | `gh issue close` / `gh pr close` restricted to fix-review only |
| **TDD** | Red → Green → Refactor. 3-layer tests required. |
| **API rate limit** | Orchestrator caches GitHub API responses (25s TTL) |
| **Logging** | All agent output persisted to `.agent-logs/` |
| **Stale cleanup** | Agents prune merged worktrees on cycle start |

---

## 📁 Skills

| Skill | Category |
|-------|----------|
| `clean-ddd-hexagonal` | Backend architecture |
| `bulletproof-react` | Frontend architecture |
| `frontend-design` | UI design |
| `baseline-ui` | Tailwind constraints |
| `fixing-accessibility` | Accessibility |
| `fixing-metadata` | SEO/OGP |
| `fixing-motion-performance` | Animation performance |
| `quality-guidelines` | Code quality |
| `delivery-pipeline` | Delivery automation |
| `inception` | INCEPTION workflow |

All skills are available as `/slash-commands` in the interactive Kiro tab,
and as Claude Code skills under `.claude/skills/` when running with
`AI_RUNNER=claude`.

---

## 📁 Directory Structure

```
.kiro/                             # Canonical config (Kiro CLI native)
├── steering/development-rules.md  # Rules (loaded every turn)
├── skills/                        # Skills (on-demand)
├── prompts/                       # Workflows (invoke with /name)
│   ├── implement.md               #   issue → impl → PR loop
│   ├── review.md                  #   merge + Dependabot
│   ├── fix-review.md              #   fix review comments
│   ├── dev-server.md              #   keep dev servers running
│   ├── watch-main.md              #   monitor develop → E2E → promote main
│   ├── e2e-bug-hunt.md            #   Playwright patrol
│   ├── ui-audit.md                #   design quality audit
│   ├── improve.md                 #   auto-generate issues
│   └── ...
├── agents/
│   ├── default.json               #   default agent config
│   └── code-reviewer.json         #   CI review agent config
└── settings.json                  #   trust settings
.claude/                           # Claude Code mirror
├── commands → ../.kiro/prompts    # symlink (slash commands)
├── skills   → ../.kiro/skills     # symlink
├── agents/code-reviewer.md        # Claude Code subagent definition
└── settings.json                  # permission allowlist
CLAUDE.md → AGENTS.md              # symlink (loaded by Claude Code)
scripts/
├── start-pipeline.sh              # Launcher (INCEPTION → pipeline)
├── orchestrator.sh                # Dynamic role allocation
├── agent.sh                       # Agent loop wrapper
├── lib/runner.sh                  # AI runner abstraction (kiro / claude)
├── control-panel.sh               # TUI control panel (gum)
├── dashboard.sh                   # Status dashboard
└── pipeline.kdl                   # zellij layout
.github/workflows/
└── kiro-review.yml                # CI: kiro-cli-review-action
```

---

<div align="center">

[MIT](LICENSE) © [yoshimi-I](https://github.com/yoshimi-I)

</div>
