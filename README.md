<div align="center">

# 🏭 kiro-engineer-teams

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
git clone https://github.com/yoshimi-I/kiro-engineer-teams.git .
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
bash <(curl -fsSL https://raw.githubusercontent.com/yoshimi-I/kiro-engineer-teams/main/scripts/install.sh)
just setup && just start
```

---

## 🔄 Full Flow

```
just start (./scripts/start-pipeline.sh)
│
├── Step 0: Preflight
│   ├── テンプレートリポ検出 → 新リポ作成（origin差し替え）
│   └── KIRO_API_KEY 設定（GitHub Secrets）
│
├── Phase 1: INCEPTION (you + AI)
│   ├── 1. ワークスペース検出
│   ├── 2. 要件分析
│   ├── 3. ユーザーストーリー
│   ├── 4. アーキテクチャ設計
│   └── 5. Issue 自動生成 → GitHub issues
│
└── Phase 2: 自律パイプライン (zellij)
    │
    └── オーケストレーター（最小構成で開始 → 必要に応じてスケール）
        │
        ├── issue検出 → implement を1paneだけ追加（デフォルト）
        ├── レビュー指摘 → fix-review を追加
        ├── merge検出 → e2e-hunt を追加
        └── watch-main/improve → 環境変数で明示有効化した場合のみ追加
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

## 🤖 CI + Kiro Review

PRs are automatically reviewed by [kiro-cli-review-action](https://github.com/konippi/kiro-cli-review-action) on GitHub Actions.

**Setup:**
1. Get a `KIRO_API_KEY` from [app.kiro.dev](https://app.kiro.dev)
2. `just start` will prompt you to set it, or manually: `gh secret set KIRO_API_KEY`
3. The workflow runs automatically on PR creation

```yaml
# .github/workflows/kiro-review.yml
- uses: konippi/kiro-cli-review-action@v1
  with:
    kiro_api_key: ${{ secrets.KIRO_API_KEY }}
    trigger_phrase: /review          # comment "/review" on a PR for on-demand review
  env:
    GITHUB_TOKEN: ${{ github.token }} # required for GitHub MCP server
```

> ⚠️ `GITHUB_TOKEN` must be passed via `env`. Without it, the GitHub MCP server fails to start and reviews won't be posted.

> ⚠️ Do not use `@kiro` as trigger phrase — it sends a mention notification to an unrelated GitHub user.

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
| [Kiro CLI](https://kiro.dev/docs/cli/) | See [downloads](https://kiro.dev/downloads/) | ✅ |
| [zellij](https://zellij.dev/) | `brew install zellij` | ✅ 0.44.1+ |
| [GitHub CLI](https://cli.github.com/) | `brew install gh` → `gh auth login` | ✅ |
| [gum](https://github.com/charmbracelet/gum) | `brew install gum` | ✅ (for control panel) |
| [jq](https://jqlang.github.io/jq/) | `brew install jq` | ✅ |
| [just](https://just.systems/) | `brew install just` | Optional |

zellij **0.44.1 or newer is required**. The orchestrator depends on the newer CLI automation APIs: `list-panes --json`, pane IDs, `--tab-id`, and `--close-on-exit`. Older versions such as `0.43.1` cannot run the dynamic pane lifecycle correctly.

```bash
zellij --version
brew upgrade zellij
```

The orchestrator uses an AI planner prompt (`.kiro/prompts/orchestrator-plan.md`) by default. Bash gathers GitHub, PR, pane, project, and post-merge state, asks the planner for a JSON action plan, validates that JSON, then launches only the approved zellij panes. The planner decides which roles to run (`dev-server`, `implement`, `review`, `fix-review`, `e2e`, `e2e-bug-hunt`, `ui-audit`, `watch-main`, `improve`) and how many `implement` panes to run based on dependencies, likely file conflicts, active panes, and review/e2e needs. Issues labeled `blocked` or waiting on an open `depends-on: #N` dependency are not considered ready. If AI planning fails, Bash falls back to dependency-aware scaling.

`watch-main` now runs as a resident develop-to-main promotion monitor by default and can be disabled with `ORCH_AUTO_WATCH_MAIN=false`. `ui-audit` auto-spawns by default after merges and can be disabled with `ORCH_AUTO_UI_AUDIT=false`. Optional `improve` auto-spawn can be enabled with `ORCH_AUTO_IMPROVE=true`. AI planning can be disabled with `ORCH_AI=false`.

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
│   ├── watch-main.md              #   monitor develop → E2E → promote main
│   ├── e2e-bug-hunt.md            #   Playwright patrol
│   ├── ui-audit.md                #   design quality audit
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
