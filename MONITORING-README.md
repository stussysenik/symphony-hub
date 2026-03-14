# Symphony Agent Monitoring Demo

Interactive monitoring tools to watch Symphony agents work in real-time.

## Quick Start

```bash
# Interactive demo launcher (recommended)
./demo.sh

# Or launch multi-pane monitoring directly
./watch-demo.sh v0-ipod CRE-5
```

## Available Monitoring Tools

### 1. **demo.sh** - Interactive Launcher
One-command demo that opens the web dashboard and provides a menu of monitoring options.

```bash
./demo.sh [project]
```

**Features:**
- Opens Phoenix web dashboard automatically
- Menu-driven interface
- Handles missing dependencies gracefully
- Perfect for first-time users

### 2. **watch-demo.sh** - Multi-Pane tmux View
Complete monitoring dashboard with 4 synchronized panes.

```bash
./watch-demo.sh [project] [issue-id]

# Example:
./watch-demo.sh v0-ipod CRE-5
```

**Layout:**
```
┌─────────────────────┬─────────────────────┐
│ Symphony Status     │ Live Logs           │
│ (refreshes: 2s)     │ (real-time stream)  │
├─────────────────────┼─────────────────────┤
│ Workspace Monitor   │ Linear Issue Status │
│ (refreshes: 3s)     │ (refreshes: 5s)     │
└─────────────────────┴─────────────────────┘
```

**Controls:**
- `Ctrl+b` then arrow keys - Navigate between panes
- `Ctrl+b d` - Detach (keeps running)
- `tmux attach -t symphony-demo` - Reattach
- `tmux kill-session -t symphony-demo` - Exit

**Dependencies:**
- tmux: `brew install tmux`
- watch: `brew install watch`

### 3. **watch-workspace.sh** - Git & File Monitor
Shows workspace activity, git commits, and file changes.

```bash
./watch-workspace.sh <project>

# Example:
watch -c -n 3 './watch-workspace.sh v0-ipod'
```

**Shows:**
- Active git branch
- Git status (modified/staged files)
- Recent commits (last 5)
- Recently modified files (last 10)
- Workspace statistics

### 4. **watch-linear.sh** - Issue Status Monitor
Monitors Linear issue state, workpad comments, and PR attachments.

```bash
./watch-linear.sh <issue-id>

# Example:
watch -c -n 5 './watch-linear.sh CRE-5'
```

**Shows:**
- Issue state with emoji indicators
- Assignee and labels
- PR/attachment links
- Latest Codex Workpad comment
- Issue URL

**States:**
- 🧭 Triage
- ⏸️  Todo
- ⚡ In Progress
- 👀 Human Review
- 🔀 Merging
- ✅ Done
- 🔄 Rework

### 5. **watch-events.sh** - Event Highlighter
Filters and highlights important events from logs.

```bash
./watch-events.sh [project]

# Example:
./watch-events.sh v0-ipod
```

**Highlights:**
- 📝 Commits
- 🔀 Pull requests
- 🔄 State changes
- 🔧 Tool calls
- ❌ Errors
- ⚡ Agent actions

### 6. **Phoenix Web Dashboard** - Rich Web UI
Full-featured web interface with live updates.

```bash
# Open in browser
open http://localhost:4001  # v0-ipod
open http://localhost:4002  # mymind-clone-web
open http://localhost:4003  # recap
```

See [DASHBOARD-GUIDE.md](DASHBOARD-GUIDE.md) for detailed usage.

## Common Workflows

### Watch Single Agent

**Terminal approach:**
```bash
# Pane 1: Status
watch -c -n 2 './launch.sh status'

# Pane 2: Logs
./launch.sh logs v0-ipod

# Pane 3: Workspace
watch -c -n 3 './watch-workspace.sh v0-ipod'

# Pane 4: Linear
watch -c -n 5 './watch-linear.sh CRE-5'
```

**Or use tmux:**
```bash
./watch-demo.sh v0-ipod CRE-5
```

### Monitor Multiple Projects

**Dashboard view:**
```bash
# Open all dashboards
open http://localhost:4001
open http://localhost:4002
open http://localhost:4003

# Or run status in loop
watch -c -n 2 './launch.sh status'
```

### Debug Issues

**Full visibility:**
```bash
# Terminal 1: Events only
./watch-events.sh v0-ipod

# Terminal 2: Full logs
./launch.sh logs v0-ipod | tee debug.log

# Terminal 3: Workspace
watch -c -n 3 './watch-workspace.sh v0-ipod'

# Browser: Dashboard
open http://localhost:4001
```

### Track Progress

**Minimal setup:**
```bash
# Just the dashboard
open http://localhost:4001

# Or just logs
./launch.sh logs v0-ipod
```

## Understanding Agent Progress

### Token Growth Patterns

| Phase | Tokens | Turn | Activity |
|-------|--------|------|----------|
| **Reading** | 0-300K | 1 | Exploring codebase |
| **Planning** | 300K-400K | 1-2 | Creating workpad |
| **Coding** | 400K-600K | 2-10 | Writing code |
| **Finishing** | 600K+ | 10-20 | Creating PR |

### Typical Timeline

```
0-2min:   Agent starts, reads issue, creates workspace
2-5min:   Reads codebase, creates plan
5-10min:  Writes code, makes commits
10-12min: Creates PR, moves to Human Review
```

### Key Indicators

**Agent is working:**
- ✅ Turn count incrementing
- ✅ Token count growing
- ✅ Last update shows activity
- ✅ Files being modified

**Agent is stuck:**
- ❌ Turn count frozen
- ❌ Same last update message
- ❌ No file changes
- ❌ Errors in logs

**Agent finished:**
- ✅ State: "Human Review"
- ✅ PR attachment in Linear
- ✅ Disappears from Running Sessions
- ✅ Clean git status

## Monitoring Comparison

| Tool | Update Speed | Detail Level | Best For |
|------|--------------|--------------|----------|
| **Web Dashboard** | Real-time (WebSocket) | High | Overview, multiple agents |
| **tmux Multi-pane** | 2-5s refresh | Very High | Single agent deep dive |
| **Live Logs** | Real-time (stream) | Maximum | Debugging, forensics |
| **Workspace Monitor** | 3s refresh | Medium | Code changes, commits |
| **Linear Monitor** | 5s refresh | Medium | Issue state, workpad |
| **Event Highlighter** | Real-time (filter) | Medium | Key moments only |

## Tips & Tricks

### Performance

- Use web dashboard for multiple agents (lower CPU)
- Use tmux for focused monitoring (higher detail)
- Use event highlighter for long-running agents (less noise)

### Customization

**Change refresh rates:**
```bash
# Faster Linear updates (every 2s instead of 5s)
watch -c -n 2 './watch-linear.sh CRE-5'

# Slower workspace updates (every 10s)
watch -c -n 10 './watch-workspace.sh v0-ipod'
```

**Custom tmux layouts:**
```bash
# Copy and modify
cp watch-demo.sh my-custom-layout.sh
# Edit split directions, pane sizes, commands
```

**Filter logs:**
```bash
# Errors only
./launch.sh logs v0-ipod | grep -i error

# Commits only
./launch.sh logs v0-ipod | grep -i commit

# Specific agent
./launch.sh logs v0-ipod | grep "CRE-5"
```

### Troubleshooting

**Scripts not executable:**
```bash
chmod +x *.sh
```

**Missing dependencies:**
```bash
# macOS
brew install tmux watch

# Verify
which tmux watch python3 curl
```

**Linear API errors:**
```bash
# Check API key
cat .env.local | grep LINEAR_API_KEY

# Test connection
./watch-linear.sh CRE-5
```

**tmux issues:**
```bash
# Kill stuck session
tmux kill-session -t symphony-demo

# List all sessions
tmux ls

# Force detach all clients
tmux detach -a
```

**Watch not available:**
```bash
# Fallback: simple loop
while true; do clear; ./launch.sh status; sleep 2; done
```

## File Structure

```
symphony-setup/
├── demo.sh                  # Interactive launcher
├── watch-demo.sh            # tmux multi-pane
├── watch-workspace.sh       # Git/file monitor
├── watch-linear.sh          # Linear issue monitor
├── watch-events.sh          # Event highlighter
├── launch.sh                # Symphony launcher
├── DASHBOARD-GUIDE.md       # Web dashboard docs
├── MONITORING-README.md     # This file
└── logs/
    ├── v0-ipod.log
    ├── mymind-clone-web.log
    └── recap.log
```

## Examples

### Example 1: First Time User

```bash
# Launch interactive demo
./demo.sh

# Opens web dashboard automatically
# Choose option 1 for multi-pane view
# Enter issue ID: CRE-5
```

### Example 2: Power User

```bash
# Terminal 1: tmux monitoring
./watch-demo.sh v0-ipod CRE-5

# Browser: Dashboard
open http://localhost:4001

# Navigate tmux panes with Ctrl+b + arrows
# Detach with Ctrl+b d when done
```

### Example 3: Debugging

```bash
# Terminal 1: Filtered events
./watch-events.sh v0-ipod | grep ERROR

# Terminal 2: Full logs
./launch.sh logs v0-ipod | tee ~/debug-$(date +%Y%m%d-%H%M%S).log

# Terminal 3: Workspace changes
watch -c -n 3 './watch-workspace.sh v0-ipod'
```

### Example 4: Multiple Projects

```bash
# Terminal tabs/windows:
# Tab 1:
./watch-demo.sh v0-ipod CRE-5

# Tab 2:
./watch-demo.sh mymind-clone-web CRE-6

# Tab 3:
./watch-demo.sh recap CRE-7

# Or use dashboard for all:
open http://localhost:4001
```

## Resources

- **Dashboard Guide**: [DASHBOARD-GUIDE.md](DASHBOARD-GUIDE.md)
- **Symphony Launcher**: `./launch.sh --help`
- **tmux Tutorial**: `man tmux`
- **Linear API**: https://developers.linear.app

## Feedback

Created as part of the Symphony monitoring demo. For issues or improvements:
1. Test scripts individually before reporting
2. Check dependencies are installed
3. Verify Symphony is running
4. Review logs for error details

---

**Enjoy watching your Symphony agents work! 🎬**
