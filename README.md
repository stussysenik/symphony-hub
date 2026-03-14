# Symphony Hub

> Central hub for monitoring and managing Symphony autonomous agents. Watch agents work in real-time with multi-pane dashboards, Linear integration, and detailed progress tracking.

## What Is This?

**Symphony Hub** is your command center for Symphony's autonomous agent system. It provides powerful monitoring tools and workflows to watch Symphony agents work in real-time as they autonomously complete tasks from Linear issues.

**What you can do:**
- 🎬 Launch agents from Linear issues
- 👀 Monitor agents in real-time with multi-pane dashboards
- 📊 Track Linear issue progress (state, comments, PRs)
- 🔍 Watch git activity, file changes, and events
- 🌐 View agent work in Phoenix web dashboard
- 🖼️ Feed visual mockups to agents (multimodal vision)
- 🖥️ Use the Go TUI dashboard for terminal-native monitoring

## What's Included

### Custom-Built Monitoring Tools
These are **new scripts** created specifically for this demo:

| Script | Purpose |
|--------|---------|
| `demo.sh` | 🚀 Interactive launcher with menu |
| `watch-demo.sh` | 📺 4-pane tmux monitoring dashboard |
| `watch-workspace.sh` | 📂 Git/file change monitor |
| `watch-events.sh` | ⚡ Event highlighter for logs |
| `watch-linear.sh` | 📋 Linear issue status monitor |

### Linear Intake Helper

| Script | Purpose |
|--------|---------|
| `linear-new.sh` | 🧭 Open a pre-filled Linear issue composer with team/status/labels defaults |

### From Symphony (Existing)
These files are part of the Symphony system:

- `launch.sh` - Symphony's multi-instance launcher
- `projects.yml` - Project configuration
- `logs/` - Agent logs (generated at runtime)
- `pids/` - Process IDs (generated at runtime)
- `workspaces/` - Agent work directories (generated at runtime)

### Go TUI Dashboard
Terminal-native monitoring built with Go + Charm (bubbletea, bubbles, lipgloss):

| Feature | Description |
|---------|-------------|
| Issues pane | Linear issues with state, cursor navigation |
| Agents pane | Active agent status, color-coded |
| Events pane | Scrollable event stream from logs |
| Project switcher | Switch between configured projects |
| Auto-refresh | 5s Linear API, 2s log polling |

```bash
# Build and run
cd tui && make build
./launch.sh tui

# Or start everything + TUI
./launch.sh start --tui
```

### Vision: Multimodal Agent Input
Agents can SEE mockups and screenshots attached to Linear issues:
- Automatic collection of image attachments from Linear
- Scans project `design/` and `assets/` directories
- Multimodal prompts with text + images sent to Codex
- Screenshot comparison tool for implementation verification
- Optional Figma MCP integration for design tokens

See `docs/VISION.md` for the full guide.

### Documentation
- `README.md` - This file (project overview)
- `SETUP.md` - Detailed setup instructions
- `LINEAR-GOLDEN-RULE.md` - **START HERE** - Minimal quick-start guide
- `LINEAR-INTAKE.md` - Recommended intake setup for Triage + templates
- `LINEAR-WORKFLOW.md` - Complete Linear integration guide
- `MONITORING-README.md` - Monitoring tools reference
- `DASHBOARD-GUIDE.md` - Phoenix dashboard usage
- `docs/RESEARCH.md` - What we learned from Symphony
- `docs/DECISIONS.md` - Why we built Hub this way
- `docs/ARCHITECTURE.md` - How Hub is structured
- `docs/VISION.md` - Visual assets guide

---

## Quick Start (5 Minutes)

### Prerequisites
- macOS or Linux
- Symphony installed and configured
- Linear account with API access

### Setup Steps

```bash
# 1. Clone this repository
git clone https://github.com/stussysenik/symphony-hub.git
cd symphony-hub

# 2. Install dependencies (macOS)
brew install tmux watch

# 3. Configure Linear API key
cp .env.local.example .env.local
# Edit .env.local and add your Linear API key from https://linear.app/settings/api

# 4. Launch the demo
./demo.sh
```

### That's It!
The demo will:
1. Open Phoenix web dashboard at http://localhost:4001
2. Show monitoring options
3. Ready to monitor agents when you create Linear issues

---

## How It Works

### Starting Agents from Linear

Symphony watches your Linear project for new issues. To start an agent:

1. **Capture the issue in Linear**
   - Recommended: create it in `Triage` from a template and let Linear help route it
   - Fast path: create it directly in `Todo` if it is already implementation-ready
2. **Move the issue to `Todo`** when you want Symphony to pick it up
3. **Symphony detects it** (polls every few seconds)
4. **Agent starts automatically** - Creates workspace, clones repo, begins work

### Monitoring Agent Progress

#### In Linear
Watch your Linear issue for real-time updates:

- **Issue State** - Shows progress:
  - `Triage` → Intake inbox, not ready for agent execution yet
  - `Todo` → Agent hasn't started yet
  - `In Progress` → Agent actively working
  - `Human Review` → Agent finished, PR ready
  - `Done` → PR merged

- **Workpad Comments** - Detailed agent updates:
  - Task breakdown and plan
  - Progress updates
  - Environment info
  - Blockers

- **Attachments** - PR links:
  - Agent attaches PR URL when complete
  - Click to review code changes

#### In Terminal
Use monitoring scripts to watch in real-time:

```bash
# Launch full dashboard (4 panes: events, workspace, logs, Linear)
./watch-demo.sh

# Or monitor individually:
./watch-linear.sh CRE-5          # Watch specific Linear issue
./watch-workspace.sh v0-ipod     # Watch agent workspace
./watch-events.sh v0-ipod        # Watch agent events
```

#### In Web Dashboard
View Phoenix dashboard at http://localhost:4001:

- Live agent status
- Task progress
- System metrics
- Event logs

See `DASHBOARD-GUIDE.md` for detailed dashboard usage.

---

## Repository Structure

```
symphony-hub/
├── Scripts (Monitoring Tools)
│   ├── demo.sh              # Interactive launcher
│   ├── watch-demo.sh        # tmux multi-pane dashboard
│   ├── watch-workspace.sh   # Git monitor
│   ├── watch-events.sh      # Event highlighter
│   ├── watch-linear.sh      # Linear status monitor
│   └── linear-new.sh        # Pre-filled Linear issue composer launcher
│
├── Symphony Core
│   ├── launch.sh            # Multi-instance launcher (+ --tui, health)
│   └── projects.yml         # Project configuration (+ assets config)
│
├── tui/                     # Go TUI Dashboard
│   ├── main.go              # Entry point
│   ├── model.go             # Bubbletea Model
│   ├── update.go            # Message handling
│   ├── view.go              # Rendering
│   ├── theme.go             # Color palette
│   ├── help.go              # Help overlay
│   ├── Makefile             # Build targets
│   ├── components/          # Pane sub-models
│   ├── linear/              # Linear API client
│   └── parser/              # Log file parser
│
├── docs/                    # Research & Architecture
│   ├── RESEARCH.md          # What we learned
│   ├── DECISIONS.md         # Why we built it this way
│   ├── ARCHITECTURE.md      # How it's structured
│   └── VISION.md            # Visual assets guide
│
├── Documentation
│   ├── README.md            # This file
│   ├── SETUP.md             # Setup instructions
│   ├── LINEAR-GOLDEN-RULE.md # Quick-start guide
│   ├── LINEAR-INTAKE.md     # Intake setup for Triage + templates
│   ├── LINEAR-WORKFLOW.md   # Linear integration guide
│   └── MONITORING-README.md # Monitoring tools reference
│
├── Configuration
│   ├── .env.local.example   # Template (committed)
│   ├── .env.local           # Your config (NOT committed)
│   └── figma-mcp.json       # Figma MCP server config
│
├── Linear Intake Templates
│   └── linear-templates/    # Copy-ready template blueprints for Linear
│
└── Runtime (Git Ignored)
    ├── logs/                # Symphony logs
    ├── pids/                # Process IDs
    └── workspaces/          # Agent workspaces
```

---

## Documentation

- **[LINEAR-GOLDEN-RULE.md](LINEAR-GOLDEN-RULE.md)** - **START HERE** - Minimal quick-start guide
- **[LINEAR-INTAKE.md](LINEAR-INTAKE.md)** - Recommended Triage + templates setup
- **[SETUP.md](SETUP.md)** - Detailed setup and installation guide
- **[LINEAR-WORKFLOW.md](LINEAR-WORKFLOW.md)** - Complete Linear integration workflow
- **[MONITORING-README.md](MONITORING-README.md)** - Monitoring tools reference
- **[DASHBOARD-GUIDE.md](DASHBOARD-GUIDE.md)** - Phoenix dashboard guide

---

## Usage Examples

### Example 1: Watch a Specific Agent

```bash
# Create Linear issue "Add new feature" (gets ID CRE-5)
# Move it to Todo if it started in Triage
# Symphony starts agent automatically

# Monitor in real-time
./watch-linear.sh CRE-5
```

### Example 2: Full Dashboard

```bash
# Launch 4-pane monitoring dashboard
./watch-demo.sh

# You'll see:
# - Top left: Agent events (highlighted)
# - Top right: Workspace changes (git activity)
# - Bottom left: Raw logs
# - Bottom right: Linear issue status
```

### Example 3: Interactive Menu

```bash
# Launch with menu
./demo.sh

# Options:
# 1. Open Phoenix Dashboard
# 2. Watch Full Demo (tmux)
# 3. Monitor Workspace
# 4. Watch Events
# 5. Monitor Linear Issue
# 6. View Logs
# 7. Agent Status
```

---

## What Makes This Reusable

✅ **No hardcoded paths** - Scripts use relative paths
✅ **Configuration template** - `.env.local.example` for easy setup
✅ **Clear documentation** - Step-by-step guides
✅ **Dependency checks** - Scripts verify tmux, watch, python3
✅ **Protected secrets** - API keys never committed
✅ **Portable** - Works on any macOS/Linux system

Anyone can:
1. Clone this repo
2. Add their Linear API key
3. Run `./demo.sh`
4. Start monitoring their Symphony agents

---

## Troubleshooting

### Scripts not executable
```bash
chmod +x *.sh
```

### tmux not found
```bash
# macOS
brew install tmux

# Linux (Ubuntu/Debian)
sudo apt-get install tmux
```

### watch command not found
```bash
# macOS
brew install watch

# Linux (Ubuntu/Debian)
sudo apt-get install procps
```

### Phoenix dashboard not loading
```bash
# Check if Symphony is running
./launch.sh status

# Start Symphony if needed
./launch.sh start all
```

### Linear API key issues
1. Verify key is in `.env.local`
2. Get new key from https://linear.app/settings/api
3. Check key has correct permissions

---

## Security Notes

⚠️ **IMPORTANT:** This repository uses `.gitignore` to protect your secrets:

- `.env.local` is **NEVER committed** to Git
- Always use `.env.local.example` as a template
- Never share your Linear API key
- Keep this repository **private**

---

## Support & Feedback

For questions or issues:
- Check the documentation guides
- Review Symphony documentation
- Verify your Linear API key and permissions

---

## License

Symphony Hub is provided as-is for use with Symphony autonomous agents.

---

**Ready to watch agents work?** → `./demo.sh`
