# Architecture: How Hub Is Structured

> Technical architecture of Symphony Hub — layer diagram, file responsibilities,
> data flows, and component design.

---

## Layer Diagram

```
┌─────────────────────────────────────────────────────┐
│                   Symphony Hub                       │
│                                                     │
│  ┌──────────────┐  ┌────────────┐  ┌─────────────┐ │
│  │  Shell Scripts │  │  Go TUI    │  │   Config    │ │
│  │  launch.sh    │  │  bubbletea │  │ projects.yml│ │
│  │  demo.sh      │  │  bubbles   │  │ .env.local  │ │
│  │  watch-*.sh   │  │  lipgloss  │  │             │ │
│  └──────┬───────┘  └─────┬──────┘  └──────┬──────┘ │
│         │                │                 │        │
└─────────┼────────────────┼─────────────────┼────────┘
          │                │                 │
          ▼                ▼                 ▼
┌─────────────────────────────────────────────────────┐
│              Symphony API Layer                      │
│                                                     │
│  ┌──────────────┐  ┌────────────┐  ┌─────────────┐ │
│  │ Linear GraphQL│  │  Log Files │  │   Phoenix   │ │
│  │ api.linear.app│  │ logs/*.log │  │  LiveView   │ │
│  └──────────────┘  └────────────┘  └─────────────┘ │
│                                                     │
└─────────────────────────┬───────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────┐
│           Symphony Core (Elixir/OTP)                 │
│                                                     │
│  ┌──────────┐  ┌───────────┐  ┌─────────────────┐  │
│  │Orchestrator│  │AgentRunner│  │  AssetCollector │  │
│  │ (polling)  │  │ (turns)   │  │  AssetCache     │  │
│  └──────┬───┘  └─────┬─────┘  └────────┬────────┘  │
│         │            │                  │           │
│         ▼            ▼                  ▼           │
│  ┌──────────┐  ┌───────────┐  ┌─────────────────┐  │
│  │  Linear   │  │  Codex    │  │ PromptBuilder   │  │
│  │  Client   │  │ AppServer │  │ (multimodal)    │  │
│  └──────────┘  └───────────┘  └─────────────────┘  │
│                                                     │
└─────────────────────────────────────────────────────┘
```

---

## File Responsibility Map (SRP)

### Symphony Hub Repository

```
symphony-hub/
├── README.md                  # Project overview and quick start
├── SETUP.md                   # Detailed installation instructions
├── LINEAR-GOLDEN-RULE.md      # Minimal quick-start for Linear workflow
├── launch.sh                  # Multi-instance Symphony launcher
├── config.sh                  # Shared config reader for shell tools
├── demo.sh                    # Interactive menu launcher
├── watch-demo.sh              # 4-pane tmux monitoring dashboard
├── watch-workspace.sh         # Git/file change monitor
├── watch-events.sh            # Event stream highlighter
├── watch-linear.sh            # Linear issue status monitor
├── projects.yml               # Project configuration (names, slugs, limits)
├── .env.local.example         # Environment template (API keys)
├── .env.local                 # Local secrets (git-ignored)
│
├── docs/
│   ├── RESEARCH.md            # What we learned from Symphony
│   ├── DECISIONS.md           # Why we built Hub this way
│   ├── ARCHITECTURE.md        # This file — how it's structured
│   └── VISION.md              # Guide to visual asset support
│
├── tui/
│   ├── go.mod                 # Go module definition + dependencies
│   ├── main.go                # Entry point — flags, init, run
│   ├── model.go               # Bubbletea Model struct + Init()
│   ├── update.go              # Update() — message/key handling
│   ├── view.go                # View() — rendering with lipgloss
│   ├── theme.go               # Color palette + lipgloss styles
│   ├── help.go                # Help overlay component
│   ├── Makefile               # Build, run, install targets
│   │
│   ├── components/
│   │   ├── issues.go          # Linear issues table pane
│   │   ├── agents.go          # Active agents status pane
│   │   ├── events.go          # Scrollable event stream pane
│   │   └── projects.go        # Project switcher pane
│   │
│   ├── linear/
│   │   └── client.go          # Linear GraphQL API client
│   │
│   └── parser/
│       └── logs.go            # Symphony log file parser
│
├── workflows/                 # Generated workflow files (per-project)
├── logs/                      # Runtime logs (git-ignored)
├── pids/                      # Process IDs (git-ignored)
└── workspaces/                # Agent work directories (git-ignored)
```

### Runtime Boundary

There are two different local runtime surfaces:

- `symphony-hub/` is the canonical operator repository.
- `symphony-setup/` is a runtime evidence locker from older runs.

Use `symphony-setup` when you need to recover context from preserved
workspaces or logs, especially for stale Linear issues that never reached a PR.
Do not treat it as the long-lived documentation or source-code home.

### Open-AI-Symphony Repository (Modified Files)

```
symphony/elixir/lib/symphony_elixir/
├── linear/
│   ├── client.ex              # + attachments in GraphQL query
│   └── issue.ex               # + attachments field in struct
├── asset_collector.ex         # NEW: Gathers visual assets from sources
├── asset_cache.ex             # NEW: Downloads and caches assets locally
├── prompt_builder.ex          # + visual context in template rendering
├── config.ex                  # + visual analysis prompt section
├── agent_runner.ex            # + asset collection/caching in run flow
└── codex/
    ├── app_server.ex          # + multimodal input (text + images)
    └── dynamic_tool.ex        # + screenshot comparison tool
```

---

## Data Flows

### Primary: Linear Issue to PR

```
                    Linear
                      │
         GraphQL poll (every 5s)
                      │
                      ▼
               ┌─────────────┐
               │ Orchestrator │─── Finds "Todo" issues
               └──────┬──────┘    Assigns to agent slots
                      │
                      ▼
               ┌─────────────┐
               │ AgentRunner  │─── Creates workspace
               └──────┬──────┘    Clones repo
                      │
                      ▼
               ┌─────────────┐
               │PromptBuilder │─── Renders Liquid template
               └──────┬──────┘    Includes issue data + visual assets
                      │
                      ▼
               ┌─────────────┐
               │  AppServer   │─── Spawns Codex subprocess
               └──────┬──────┘    JSON-RPC over stdio
                      │
                      ▼
               ┌─────────────┐
               │  Codex Agent │─── Reads code, edits files
               └──────┬──────┘    Runs tests, creates PR
                      │
                      ▼
                   GitHub PR
                      │
               Human reviews + merges
```

### Intake: Raw Prompt to Triage Draft

```
                Raw NLP Request
                       │
                       ▼
               ┌─────────────┐
               │ launch intake│
               └──────┬──────┘
                      │
                      ▼
               ┌─────────────┐
               │ Repo Diagnose│─── fetch origin/main
               └──────┬──────┘    ahead/behind + dirty state
                      │
                      ▼
               ┌─────────────┐
               │ Evidence Scan │─── rg keyword hits + LOC
               └──────┬──────┘    auth / restriction signals
                      │
                      ▼
               ┌─────────────┐
               │ Linear Context│─── states, labels, nearby issues
               └──────┬──────┘
                      │
                      ▼
               ┌─────────────┐
               │ Bound Compile│─── richer Codex draft
               └──────┬──────┘    deterministic fallback if incomplete/slow
                      │
                      ▼
               ┌─────────────┐
               │ Draft Bundle │─── request.txt / diagnosis.json / compiled.json / draft.md
               └──────┬──────┘
                      │
              --issue target + --apply mutate gate
                      │
                      ▼
            Linear Triage or issue refresh
```

Existing-issue diagnosis reuses the same repo/evidence path, but starts from a
live Linear ticket and writes a local bundle under `diagnoses/` before
optionally commenting and applying a safe queue-state change.

The issue body itself is a separate control-plane artifact:

```
               Existing Linear Issue
                       │
                       ▼
               ┌─────────────┐
               │ issuefmt     │─── canonical heading order
               └──────┬──────┘    placeholder injection for missing required sections
                      │
                      ▼
               ┌─────────────┐
               │ Todo Gate    │─── Context / Problem / Desired Outcome
               └──────┬──────┘    Acceptance Criteria / Validation / Assets
                      │
                      ▼
               ┌─────────────┐
               │ audit +      │─── flags todo-unready-signature
               │ diagnose     │    and todo-needs-format
               └─────────────┘
```

### Vision: Asset Collection and Multimodal Input

```
               Linear Issue
                    │
                    ▼
          ┌─────────────────┐
          │ AssetCollector   │
          │                  │
          │ 1. Linear attachments (images from issue)
          │ 2. Project assets (design/ directory scan)
          │ 3. Website screenshots (future: Playwright)
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │   AssetCache     │
          │                  │
          │ Downloads images to workspace/assets/
          │ Writes manifest.json with metadata
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │  PromptBuilder   │
          │                  │
          │ Adds "Visual Context" section to prompt
          │ Lists all available visual assets
          └────────┬────────┘
                   │
                   ▼
          ┌─────────────────┐
          │   AppServer      │
          │                  │
          │ Builds multimodal input:
          │ [text_block, image_block, image_block, ...]
          │ Sends to Codex via JSON-RPC
          └─────────────────┘
```

### TUI: Dashboard Data Sources

```
   ┌──────────────────────────────────────────────┐
   │              Go TUI (bubbletea)               │
   │                                              │
   │  ┌──────────┐ ┌──────────┐ ┌──────────────┐ │
   │  │ Issues   │ │ Agents   │ │ Events       │ │
   │  │ Pane     │ │ Pane     │ │ Pane         │ │
   │  └────┬─────┘ └────┬─────┘ └──────┬───────┘ │
   │       │            │              │          │
   └───────┼────────────┼──────────────┼──────────┘
           │            │              │
           ▼            │              ▼
   ┌──────────────┐     │      ┌──────────────┐
   │ Linear API   │     │      │ Log Parser   │
   │ (GraphQL)    │     │      │ (file watch) │
   │              │     │      │              │
   │ Refresh: 5s  │     │      │ Refresh: 2s  │
   └──────────────┘     │      └──────────────┘
                        │
                        ▼
                ┌──────────────┐
                │ Derived from │
                │ Issues + Logs│
                └──────────────┘
```

---

## TUI Component Tree

```
Program (tea.NewProgram)
│
└── Model
    ├── Active Pane Index (0-3)
    ├── Window Size (width, height)
    ├── Show Help (bool)
    │
    ├── Issues Component (components/issues.go)
    │   ├── bubbles/table
    │   ├── Columns: ID, Title, State, Updated
    │   └── Data source: Linear GraphQL client
    │
    ├── Agents Component (components/agents.go)
    │   ├── bubbles/table
    │   ├── Columns: Name, Status, Issue, Duration
    │   └── Data source: Derived from issues + logs
    │
    ├── Events Component (components/events.go)
    │   ├── bubbles/viewport
    │   ├── Scrollable, color-coded by type
    │   └── Data source: Log parser
    │
    └── Projects Component (components/projects.go)
        ├── bubbles/list
        ├── Project names from config
        └── Highlight active, Enter to switch
```

---

## Configuration

### projects.yml Structure

```yaml
defaults:           # Global defaults for all projects
  max_agents: 2     # Max concurrent agents per project
  polling_interval_ms: 5000
  max_turns: 20     # Max Codex turns per issue

symphony_bin: "..."  # Path to Symphony Elixir binary
engine:
  repo_root: "/path/to/open-ai-symphony/symphony"
  fork_url: "https://github.com/your-user/symphony.git"
  upstream_url: "https://github.com/openai/symphony.git"
  expected_branch: "main"
base_port: 4001      # Phoenix dashboard starting port
workspace_root: "..."
logs_root: "..."
workflows_dir: "..."

projects:
  - name: "project-name"
    github_url: "..."
    repo_root: "/path/to/local/repo"
    linear_project_slug: "..."
    max_agents: 2
    default_branch: "main"
    workspace_strategy: "worktree" # or "clone"
    workflow_appendix: "workflow-instructions/project-name.md"
    assets:                    # Visual asset configuration
      collect_attachments: true
      scan_project_dirs: true
      capture_screenshots: false
      supported_formats: [png, jpg, gif, webp, svg, figma]
```

### Environment Variables

```
LINEAR_API_KEY       # Required: Linear API authentication
FIGMA_ACCESS_TOKEN   # Optional: Figma MCP integration
```
