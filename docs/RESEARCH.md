# Research: What We Learned from Symphony

> Findings from studying the Symphony autonomous agent system (Elixir/OTP).
> This document captures how Symphony works under the hood so we can build
> effective monitoring and extension tooling around it.

---

## Symphony Architecture

### Elixir/OTP Foundation

Symphony is built on Elixir's OTP (Open Telecom Platform) — a battle-tested
framework for building concurrent, fault-tolerant systems. Key patterns:

- **GenServer processes** — Each agent runs as a supervised GenServer, meaning
  crashes are automatically recovered. This is why agents can run for hours
  without manual babysitting.
- **Supervisor trees** — Processes are organized hierarchically. If a child
  crashes, the supervisor decides whether to restart it, restart all siblings,
  or escalate. Symphony uses `one_for_one` strategy (restart only the crashed
  agent, leave others running).
- **Message passing** — Processes communicate via async messages, not shared
  memory. This eliminates race conditions and makes the system naturally
  concurrent.

### Orchestrator: The Brain

The `Orchestrator` module is Symphony's central coordinator:

1. **Polls Linear** every few seconds for issues in "Todo" state
2. **Assigns issues** to available agent slots (respects `max_agents` per project)
3. **Manages lifecycle** — starts agents, monitors progress, handles completion
4. **State machine** — Drives issues through: Todo -> In Progress -> Human Review -> Done

The Orchestrator is NOT an agent — it's a dispatcher. It never writes code.

### Codex App Server: The Worker

Each agent is actually an OpenAI Codex instance managed by `AppServer`:

- **JSON-RPC over stdio** — Communication uses stdin/stdout JSON-RPC protocol,
  not HTTP. The Elixir process spawns a Codex CLI subprocess and communicates
  via pipes.
- **Turn-based execution** — Each "turn" sends a prompt and waits for Codex to
  complete. Multiple turns allow retry logic and continuation.
- **Workspace isolation** — Each agent gets its own directory (cloned repo),
  preventing agents from stepping on each other's work.
- **Dynamic tools** — Agents can call back into Symphony (e.g., query Linear
  via GraphQL) through registered tool handlers.

### Phoenix LiveView Dashboards

Each project gets a Phoenix LiveView dashboard on its own port:

- **Base port: 4001** — First project gets 4001, second gets 4002, etc.
- **Real-time updates** — LiveView pushes changes over WebSocket, no polling
- **Per-project isolation** — Each dashboard only shows its own project's data
- **Built-in to Symphony** — Not an add-on; it's part of the Elixir app

---

## Linear Integration

### GraphQL Polling Model

Symphony doesn't use Linear webhooks. Instead:

1. **Polls via GraphQL** — Periodic HTTP POST to `api.linear.app/graphql`
2. **Filters by project slug** — Each project has a `linear_project_slug` in config
3. **Fetches rich data** — Issue title, description, state, assignee, labels,
   branch name, related issues, timestamps
4. **Detects state changes** — Compares current state against known state to
   trigger actions

Why polling over webhooks? Simpler deployment (no public endpoint needed),
works behind firewalls, and Linear's rate limits are generous enough for
5-second intervals.

### State Machine

Issues flow through a well-defined state machine:

```
Todo          — Agent hasn't started yet (trigger state)
In Progress   — Agent actively working (set by Orchestrator)
Human Review  — Agent finished, PR ready (set by agent)
Done          — PR merged (set by human)
Cancelled     — Work abandoned (set by human)
```

The Orchestrator only picks up issues in "Todo" state. All other transitions
are driven by agent completion or human action.

### Workpad Comments

Agents post structured updates to the Linear issue's workpad:

- **Task breakdown** — Agent's plan before starting
- **Progress updates** — Checkmarks as tasks complete
- **Environment info** — Workspace, branch, repo details
- **Blockers** — If the agent gets stuck
- **PR link** — Final attachment with GitHub PR URL

---

## Key Gaps Found

These gaps motivated building Symphony Hub:

1. **No visual/asset support** — Agents receive text-only prompts. They can't
   see mockups, screenshots, or design files attached to Linear issues.
2. **No TUI** — Monitoring requires either the Phoenix web dashboard or manual
   log tailing. No terminal-native dashboard for CLI-first workflows.
3. **No cross-project view** — Phoenix dashboards are per-project. No way to
   see all agents across all projects at once.
4. **No offline monitoring** — Phoenix requires Symphony to be running. Can't
   review past agent activity when Symphony is stopped.
5. **No configuration UI** — Projects are configured by editing YAML and
   Elixir config files manually.

---

## Data Flow: Issue to PR

```
Linear Issue (Todo)
    |
    v
Orchestrator polls Linear GraphQL
    |
    v
Orchestrator assigns issue to agent slot
    |
    v
AppServer spawns Codex subprocess (JSON-RPC over stdio)
    |
    v
PromptBuilder renders Liquid template with issue data
    |
    v
Codex agent works in isolated workspace (git clone, edit, test)
    |
    v
Agent creates PR via GitHub API
    |
    v
Agent posts PR link to Linear, sets state to Human Review
    |
    v
Human reviews PR, merges, sets state to Done
```

---

## Technology Stack Reference

| Layer | Technology | Why |
|-------|-----------|-----|
| Runtime | Elixir/OTP | Concurrency, fault tolerance, hot code reload |
| Process model | GenServer + Supervisor | Crash recovery, state management |
| Web dashboard | Phoenix LiveView | Real-time UI without JavaScript |
| Template engine | Solid (Liquid) | Safe templating for prompts |
| API client | HTTPoison | HTTP requests to Linear/GitHub |
| JSON parsing | Jason | Fast JSON encode/decode |
| Agent engine | OpenAI Codex CLI | Code generation and editing |
| IPC protocol | JSON-RPC over stdio | Subprocess communication |
| Config format | YAML + Markdown | Human-readable project/workflow config |
