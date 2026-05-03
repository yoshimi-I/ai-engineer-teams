<div align="center">

# 🏭 kiro-engineer-teams

**12-agent orchestrated development pipeline**
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
git clone https://github.com/yoshimi-I/kiro-engineer-teams.git .
```

**2. Install prerequisites**
```bash
./scripts/setup.sh
```

**3. Initialize as your own private repo**
```bash
just init
```

**4. Start (INCEPTION → orchestrated pipeline)**
```bash
just start
```

---

## 📥 Add to Existing Project

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/yoshimi-I/kiro-engineer-teams/main/scripts/install.sh)
just setup && just start
```

---

## 🔄 Full Flow

```
./scripts/start-pipeline.sh
│
├── Phase 1: INCEPTION (you + AI)
│   ├── 1. Workspace Detection
│   ├── 2. Requirements Analysis
│   ├── 3. User Stories
│   ├── 4. Architecture Design
│   └── 5. Issue Generation → GitHub issues
│
└── Phase 2: Orchestrated Pipeline (fully autonomous)
    │
    ├── Orchestrator polls GitHub every 30s
    │   ├── issues多い → Impl多め
    │   ├── PR溜まってる → Review多め
    │   └── 仕事なし → idle
    │
    └── 12 panes dynamically assigned:
        ├── Dev-Server, Impl ×N, Review ×N
        ├── Fix-Review ×N, Watch-Main, E2E-Hunt
        └── Improve
```

---

## 🖥️ Zellij Tabs

| Tab | Key | Content |
|-----|-----|---------|
| **Pipeline** | Alt+1 | Orchestrator — dynamically assigns 12 panes |
| **Control** | Alt+2 | TUI control panel — status, stop/restart, logs, current work |
| **Kiro** | Alt+3 | Interactive kiro-cli — use `/slash-commands` manually |

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

## 🤖 CI + Kiro Review

PRs are automatically reviewed by [kiro-cli-review-action](https://github.com/konippi/kiro-cli-review-action) on GitHub Actions.

```yaml
# .github/workflows/kiro-review.yml
on:
  pull_request: [opened, ready_for_review, synchronize]
  issue_comment: [created]  # @kiro trigger
```

| Role | CI Kiro Review | Local Review Agent |
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
Orchestrator (polls every 30s, assigns roles to 12 panes)
    │
    ├── Impl agents → pick issue → implement → PR
    │                                │
    │                    CI: kiro-cli-review-action
    │                                │
    │                         ┌──────┴──────┐
    │                      🟢 LGTM      🔴 Fix needed
    │                         │              │
    │                    Local Review    Fix-Review agent
    │                    agent merges    fixes → re-push
    │                         │
    │                    main merged
    │                         │
    ├── Watch-Main → E2E verification → bug issues
    ├── E2E-Hunt → Playwright patrol → bug issues
    └── Improve → auto-generate improvement issues
```

---

## 📋 Prerequisites

| Tool | Install | Required |
|------|---------|:---:|
| [Kiro CLI](https://kiro.dev/docs/cli/) | See [downloads](https://kiro.dev/downloads/) | ✅ |
| [zellij](https://zellij.dev/) | `brew install zellij` | ✅ |
| [GitHub CLI](https://cli.github.com/) | `brew install gh` → `gh auth login` | ✅ |
| [gum](https://github.com/charmbracelet/gum) | `brew install gum` | ✅ (for control panel) |
| [jq](https://jqlang.github.io/jq/) | `brew install jq` | ✅ |
| [just](https://just.systems/) | `brew install just` | Optional |

---

## 🛡️ Guardrails

| Category | Rules |
|----------|-------|
| **Git safety** | No direct push to main. No `--force`. No `git branch -D`. Squash merge only. |
| **Editor prevention** | `GIT_EDITOR=true` + `git config --global core.editor true` (3-layer) |
| **Filesystem** | No operations above project root. No `cd ..` or `../` paths. |
| **Issue limits** | improve: 3/cycle, e2e-bug-hunt: 5/cycle, watch-main: 3/cycle |
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
| `terraform-style-guide` | IaC (Terraform) |
| `aws-cdk-development` | IaC (CDK) |
| `ci-cd-pipeline-patterns` | CI/CD |
| `database-migration` | DB schema changes |
| `monitoring-observability` | Monitoring/alerting |
| `react-native-best-practices` | Mobile (React Native) |
| `etl-pipeline` | Data pipelines |

All skills are available as `/slash-commands` in the interactive Kiro tab.

---

## 📁 Directory Structure

```
.kiro/
├── steering/development-rules.md  # Rules (loaded every turn)
├── skills/                        # 15 skills (on-demand)
├── prompts/                       # Workflows (invoke with /name)
│   ├── implement.md               #   issue → impl → PR loop
│   ├── review.md                  #   merge + Dependabot
│   ├── fix-review.md              #   fix review comments
│   ├── dev-server.md              #   keep dev servers running
│   ├── watch-main.md              #   monitor main → E2E
│   ├── e2e-bug-hunt.md            #   Playwright patrol
│   ├── improve.md                 #   auto-generate issues
│   └── ...
├── agents/
│   ├── default.json               #   default agent config
│   └── code-reviewer.json         #   CI review agent config
└── settings.json                  #   trust settings
scripts/
├── start-pipeline.sh              # Launcher (INCEPTION → pipeline)
├── orchestrator.sh                # Dynamic role allocation
├── agent.sh                       # Agent loop wrapper
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
