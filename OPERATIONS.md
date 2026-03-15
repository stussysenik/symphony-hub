# Symphony Operations Guide

The operator's playbook for running Symphony autonomous agents end-to-end: from Linear issue to merged PR to cleaned-up workspace.

---

## How It All Fits Together

```mermaid
flowchart TD
    subgraph You["You (Operator)"]
        A1[Create Linear issue] --> A2[Move to Todo]
        A5[Review PR on GitHub] --> A6{Approve?}
        A6 -->|Yes| A7[Move ticket to Merging]
        A6 -->|No| A8[Add review comments]
    end

    subgraph Symphony["Symphony (Orchestrator)"]
        B1[Polls Linear] --> B2[Detects Todo issue]
        B2 --> B3[Creates workspace + worktree]
        B3 --> B4[Dispatches Codex agent]
    end

    subgraph Agent["Codex Agent"]
        C1[Implements code] --> C2[commit + push skills]
        C2 --> C3[Creates PR on GitHub]
        C3 --> C4[Moves ticket to Human Review]
        C5[Runs land skill] --> C6[Squash-merges PR]
        C6 --> C7[Moves ticket to Done]
        C8[Addresses feedback] --> C2
    end

    subgraph Cleanup["Cleanup"]
        D1[Orchestrator detects Done state]
        D1 --> D2[before_remove hook fires]
        D2 --> D3[git worktree remove + prune]
    end

    A2 --> B1
    B4 --> C1
    C4 --> A5
    A7 --> C5
    A8 --> C8
    C7 --> D1
```

---

## The Operator Workflow

This is the repeatable loop you run for every batch of agent work.

### 1. Start

```bash
cd ~/Desktop/symphony-hub
./launch.sh start mymind-clone-web     # Start orchestrator + dashboard
```

### 2. Monitor

Pick your preferred surface:

| Method | Command / URL |
|--------|---------------|
| Web dashboard (real-time) | `open http://localhost:4002` |
| TUI terminal dashboard | `./launch.sh --tui` |
| Tail logs | `tail -f ~/Desktop/open-ai-symphony/symphony/elixir/log/symphony.log` |
| JSON API — full state | `curl http://localhost:4002/api/v1/state` |
| JSON API — single issue | `curl http://localhost:4002/api/v1/CRE-6` |
| JSON API — force poll | `curl -X POST http://localhost:4002/api/v1/refresh` |

### 3. Review

Agents create PRs automatically and move the Linear ticket to **Human Review**.

- Go to the PR on GitHub (link is in the Linear ticket and dashboard)
- Review the diff, run the app locally if needed:
  ```bash
  cd ~/Desktop/symphony-setup/workspaces/mymind-clone-web/CRE-6
  cat PROGRESS.md                    # What the agent did
  git diff origin/main --stat        # Summary of changes
  bun install && bun run dev         # Start dev server at localhost:3000
  ```
- **Approve** → move ticket to `Merging`
- **Request changes** → add review comments on the PR; the agent picks them up and pushes a new revision

### 4. Land

Once you move the ticket to **Merging**, the agent automatically:
1. Runs the `land` skill
2. Squash-merges the PR
3. Moves the ticket to **Done**

**Batch landing**: If you have many PRs ready, move them all to `Merging` at once — agents handle the rest sequentially.

### 5. Cleanup

When a ticket hits **Done**, the orchestrator automatically:
1. Fires the `before_remove` hook
2. Runs `git worktree remove` for the workspace
3. Runs `git worktree prune`

No manual cleanup required.

---

## When Things Go Wrong

### Agent didn't push or create a PR

Go to the workspace and do it manually:

```bash
cd ~/Desktop/symphony-setup/workspaces/mymind-clone-web/CRE-6
git add -A
git commit -m "feat(tags): implement tag prioritization

Closes CRE-6"
git push origin feature/CRE-6
gh pr create --base main --head feature/CRE-6 \
  --title "feat(tags): implement tag prioritization"
```

### Merge conflicts between agent branches

When multiple agents work on overlapping code, land PRs sequentially:

1. Pick the most independent PR first and merge it
2. The next agent's `land` skill will auto-rebase before merging
3. If rebase fails, go to the workspace and resolve manually:
   ```bash
   cd ~/Desktop/symphony-setup/workspaces/mymind-clone-web/CRE-8
   git fetch origin main
   git rebase origin/main
   # resolve conflicts
   git push --force-with-lease origin feature/CRE-8
   ```

### Stale workspaces

If workspaces linger after tickets are Done:

```bash
cd ~/Desktop/mymind-clone-web
git worktree list                    # See all worktrees
git worktree remove ~/Desktop/symphony-setup/workspaces/mymind-clone-web/CRE-6
git worktree prune                   # Clean up stale references
```

### Agent errors

1. Check the log: `tail -100 ~/Desktop/open-ai-symphony/symphony/elixir/log/symphony.log`
2. Check the dashboard for error badges at `http://localhost:4002`
3. Retry by moving the ticket back to **Todo** in Linear — Symphony re-detects and restarts

---

## Three-Repo Relationship

```
symphony-hub (github.com/stussysenik/symphony-hub)
  Role: Operator interface — TUI, launch scripts, workflow configs, project definitions
  Language: Go + Shell
  Key files: launch.sh, projects.yml, workflows/*.md
        |
        | launches
        v
open-ai-symphony (github.com/stussysenik/symphony)
  Role: Core engine — orchestrator, dashboard, Codex client, workspace management
  Language: Elixir/OTP
  Fork of: github.com/openai/symphony
  Key files: orchestrator.ex, app_server.ex, agent_runner.ex, event_log.ex
        |
        | creates worktrees in
        v
mymind-clone-web (github.com/stussysenik/mymind-clone-web)
  Role: Product repo — agent PRs land here
  Language: TypeScript (Next.js)
  Runtime workspace: ~/Desktop/symphony-setup/workspaces/mymind-clone-web/
```

---

## Versioning & Tagging

| Repo | Tag format | Example |
|------|-----------|---------|
| symphony-hub | `v{major}.{minor}.{patch}` | `v0.2.0` |
| open-ai-symphony | `custom/{feature}-v{n}` | `custom/dashboard-v1` |
| mymind-clone-web | `v{major}.{minor}.{patch}` | `v0.5.0` |

### symphony-hub

```bash
cd ~/Desktop/symphony-hub
git tag -a v0.2.0 -m "Dashboard revamp + workflow configs"
git push origin main --tags
```

### open-ai-symphony (fork management)

You have `origin` (your fork) and `upstream` (OpenAI):

```bash
cd ~/Desktop/open-ai-symphony/symphony

# Push your changes
git push origin main

# Sync from upstream periodically
git fetch upstream
git merge upstream/main

# Tag your customizations
git tag -a custom/dashboard-v1 -m "Dashboard revamp with event stream"
git push origin main --tags
```

### mymind-clone-web

```bash
cd ~/Desktop/mymind-clone-web
# After squash-merging all agent PRs:
git pull origin main
git tag -a v0.5.0 -m "CRE-6, CRE-8, CRE-11 agent work"
git push origin main --tags
```

---

## CLI Reference

### launch.sh

```bash
./launch.sh start <project>          # Start orchestrator + dashboard
./launch.sh stop <project>           # Stop gracefully
./launch.sh health                   # Check if running
./launch.sh --tui                    # Start with TUI monitor
./launch.sh tui                      # Launch TUI standalone
./launch.sh status                   # Show running instances
```

### API Endpoints (localhost:4002)

| Endpoint | Method | Description |
|----------|--------|-------------|
| `/api/v1/state` | GET | Full orchestrator state |
| `/api/v1/<issue-id>` | GET | Single issue detail |
| `/api/v1/refresh` | POST | Force Linear poll |

### Monitoring Scripts

```bash
./watch-demo.sh                      # 4-pane tmux dashboard
./watch-linear.sh CRE-5              # Watch specific Linear issue
./watch-workspace.sh <workspace>     # Watch git/file changes
./watch-events.sh <workspace>        # Watch agent event stream
./linear-new.sh                      # Open pre-filled Linear issue composer
```

### Agent Workspace Inspection

```bash
cd ~/Desktop/symphony-setup/workspaces/mymind-clone-web/CRE-6
cat PROGRESS.md                      # Agent's progress notes
cat LEARNING.md                      # Agent's learning notes
git diff origin/main --stat          # Summary of changes
git diff origin/main                 # Full diff
ls pr-screenshots/                   # Visual artifacts
```

---

## What You Can See About Agent Reasoning

### Available today

| Data | Where | How to access |
|------|-------|---------------|
| Event stream | EventLog GenServer (in-memory) | Dashboard at `localhost:4002` |
| Last codex message per issue | Orchestrator snapshot | Dashboard running sessions |
| Token usage (input/output/total) | Orchestrator snapshot | Dashboard metric cards |
| Token delta per event | EventLog metadata | Dashboard event stream `+Nt` badges |
| Rate limits | Orchestrator snapshot | Dashboard rate limits section |
| Disk logs + ingestion summaries | `log/symphony.log` (rotating, 50MB) | `tail -f` or read directly |
| Agent's git diff | Workspace on disk | `git diff origin/main` in workspace |
| Progress notes | `PROGRESS.md` in each workspace | Read the file |
| Learning notes | `LEARNING.md` in each workspace | Read the file |
| Visual artifacts | `pr-screenshots/` in workspace | View PNG/SVG files |

### Not available (protocol limitations)

| Missing Data | Why |
|--------------|-----|
| Full prompt sent to Codex | Partially logged (ingestion_summary in symphony.log) |
| Thinking traces / chain-of-thought | Codex doesn't expose internal reasoning |
| Full conversation history | Lives inside Codex session, not exported |

---

## Why Claude Code Can't Replace Codex

They speak different protocols. It's not a config swap.

| | Codex `app-server` | Claude Code `--print` |
|---|---|---|
| Protocol | JSON-RPC 2.0 bidirectional over stdio | One-shot text in / text out |
| Tool execution | Structured `item/tool/call` requests | Internal, not interceptable |
| Approval flow | Pause / ask orchestrator / resume | Pre-configured flag |
| Multi-turn | Thread reuse across turns | Each invocation is independent |
| Token tracking | Live `tokenUsage/updated` notifications | Not exposed |

**Option A — Change the model, not the CLI** (easiest): Use `codex --model claude-sonnet-4-5-20250929 app-server` if your Codex version supports Anthropic models.

**Option B — Wait for `claude app-server`**: If Anthropic ships a JSON-RPC app-server mode, it would be a drop-in replacement.

**Option C — Build a new AgentRunner** (significant work): Replace `AppServer` with a module that invokes `claude --print` per-turn. Loses approval negotiation, live token tracking, and sandbox enforcement.
