# Symphony Dashboard Guide

## Accessing Dashboards

Each project has its own Phoenix LiveView dashboard:

- **v0-ipod**: http://localhost:4001
- **mymind-clone-web**: http://localhost:4002
- **recap**: http://localhost:4003

## Dashboard Features

### 1. Metrics Cards (Top Row)

**Running** - Number of active agents currently working
**Retrying** - Number of issues in backoff/retry queue
**Total Tokens** - Cumulative tokens (input | output split)
**Runtime** - Total elapsed time for all sessions

### 2. Running Sessions Table

Shows active agents with:
- **Issue ID** - Linear issue identifier with color-coded status
- **State** - Current workflow state (Todo, In Progress, etc.)
- **Session** - Codex session ID (click to copy)
- **Runtime / Turn** - How long agent has been running and current turn number
- **Last Update** - Most recent agent activity with timestamp
- **Tokens** - Token count for this session

### 3. Retry Queue Table

Shows issues waiting to retry after errors:
- **Issue ID** - Linear issue identifier
- **Attempt** - Retry attempt number
- **Due** - When the next retry will occur
- **Error** - Error message that triggered retry

### 4. Rate Limits Section

Raw JSON display of upstream API rate limit information:
- Requests remaining
- Reset timestamp
- Current usage

### 5. Live Updates

Dashboard auto-updates via WebSocket:
- **Event-driven updates** - Changes appear instantly when agents act
- **Periodic refresh** - Status refreshes every 1 second
- **No manual reload needed** - Page stays current automatically

## What to Watch

### Agent Starting
1. Issue appears in "Running Sessions" table
2. State shows "Todo"
3. Session ID appears
4. Last Update shows "no codex message yet"

### Agent Working
1. State changes to "In Progress"
2. Turn count increments
3. Token count increases
4. Last Update shows current activity (e.g., "reasoning", "tool call")

### Agent Creating PR
1. State changes to "Human Review"
2. Last Update shows "PR created"
3. Check Linear issue for PR attachment
4. Runtime stops incrementing

### Agent Completion
1. Issue disappears from "Running Sessions"
2. Total tokens and runtime update
3. Issue moved to Done in Linear

## Tips

- **Keep dashboard open** while working on other tasks
- **Watch token count** to gauge agent progress
- **Monitor turn count** - max is 20 by default
- **Check Last Update** for current agent activity
- **Use Session ID** to correlate with logs

## Keyboard Shortcuts

- **Cmd/Ctrl + R** - Manually refresh (usually not needed)
- **Cmd/Ctrl + Click Session ID** - Copy session ID to clipboard

## Troubleshooting

**Dashboard not loading?**
- Check Symphony is running: `./launch.sh status`
- Verify port is correct (4001, 4002, or 4003)
- Check logs: `./launch.sh logs <project>`

**Not updating?**
- Check browser console for WebSocket errors
- Ensure JavaScript is enabled
- Try hard refresh: Cmd/Ctrl + Shift + R

**Shows old data?**
- WebSocket may have disconnected
- Hard refresh the page
- Check Symphony instance is still running

## Monitoring Workflow

### Quick Start
```bash
# Open dashboard
open http://localhost:4001

# Start multi-pane monitoring in terminal
./watch-demo.sh v0-ipod CRE-5
```

### Advanced Monitoring

**Terminal Status:**
```bash
watch -c -n 2 './launch.sh status'
```

**Live Logs:**
```bash
./launch.sh logs v0-ipod
```

**Workspace Monitor:**
```bash
watch -c -n 3 './watch-workspace.sh v0-ipod'
```

**Linear Status:**
```bash
watch -c -n 5 './watch-linear.sh CRE-5'
```

**Event Highlights:**
```bash
./watch-events.sh v0-ipod
```

### Full Demo
```bash
./demo.sh v0-ipod
```

## Understanding Agent Progress

### Token Growth Patterns

**Reading Phase (0-300K tokens):**
- Rapid input token growth
- Agent exploring codebase
- Turn count stays at 1
- Few or no output tokens

**Planning Phase (300K-400K tokens):**
- Slower token growth
- Agent creating plan
- Turn count increments
- Output tokens increase (workpad creation)

**Coding Phase (400K-600K tokens):**
- Steady token growth
- Agent writing code
- Turn count 2-10
- Output tokens grow with file edits

**Finishing Phase (600K+ tokens):**
- Token growth slows
- Agent creating PR
- Turn count approaches 20
- State changes to "Human Review"

### Turn Count Indicators

- **Turn 1-3:** Initial exploration and planning
- **Turn 4-8:** Active coding and commits
- **Turn 9-15:** Testing, refinement, PR preparation
- **Turn 16-20:** Final adjustments and completion

### State Transitions

```
Todo → In Progress → Human Review → Merging → Done
                  ↓
                Rework (if changes requested)
```

## Dashboard Comparison

| Feature | Web Dashboard | Terminal tmux | Logs | Linear |
|---------|--------------|---------------|------|--------|
| Real-time updates | ✅ WebSocket | ✅ watch/tail | ✅ tail -f | ⏱️ Polling |
| Token metrics | ✅ Detailed | ✅ Summary | ❌ | ❌ |
| Workspace files | ❌ | ✅ | ❌ | ❌ |
| Git commits | ❌ | ✅ | ⚠️ Partial | ❌ |
| Issue state | ✅ | ⚠️ Basic | ❌ | ✅ Detailed |
| Workpad comments | ❌ | ❌ | ❌ | ✅ |
| PR links | ❌ | ❌ | ❌ | ✅ |
| Multi-project | ✅ Tabs | ⚠️ Manual | ✅ | ⚠️ Manual |

**Recommendation:** Use web dashboard + tmux together for complete visibility.

## Common Patterns

### Monitoring Active Development

1. **Open web dashboard** - http://localhost:4001
2. **Launch tmux session** - `./watch-demo.sh v0-ipod CRE-5`
3. **Position windows** - Dashboard in browser, tmux in terminal
4. **Watch both** - Dashboard for overview, tmux for details

### Debugging Stuck Agents

1. **Check dashboard** - Is turn count incrementing?
2. **Check logs** - Look for errors or repeated patterns
3. **Check workspace** - Are files being modified?
4. **Check Linear** - Is workpad being updated?

### Tracking Multiple Agents

1. **Use web dashboard** - Shows all agents in one view
2. **Switch tmux sessions** - One per agent/issue
3. **Use event highlighter** - `./watch-events.sh` for key moments
4. **Check Linear project** - Overview of all issues

## Example Session

### Scenario: Watching agent implement a feature

**Setup:**
```bash
# Terminal 1: Multi-pane monitoring
./watch-demo.sh v0-ipod CRE-5

# Browser: Web dashboard
open http://localhost:4001
```

**What you'll see:**

**Minute 0-2 (Starting):**
- Dashboard shows CRE-5 in "Todo"
- Logs show workspace creation
- Workspace monitor shows empty directory
- Linear shows issue unassigned

**Minute 2-5 (Reading):**
- State → "In Progress"
- Tokens: 50K → 200K
- Workspace shows git clone
- Linear shows agent workpad comment

**Minute 5-10 (Coding):**
- Turn count: 2 → 5
- Workspace shows git commits
- Tokens: 200K → 500K
- Linear workpad updates with progress

**Minute 10-12 (Finishing):**
- Turn count: 8 → 10
- Workspace shows final commits
- State → "Human Review"
- Linear shows PR attachment

**Minute 12+ (Complete):**
- Agent disappears from dashboard
- Workspace shows clean state
- Linear shows completed issue
- PR ready for review

## Advanced Tips

### Custom Layouts

Create your own tmux layout:
```bash
# Copy watch-demo.sh and modify pane layout
cp watch-demo.sh my-layout.sh
# Edit to change split directions, sizes, commands
```

### Filter Logs

Show only errors:
```bash
./launch.sh logs v0-ipod | grep -i error
```

Show only commits:
```bash
./launch.sh logs v0-ipod | grep -i commit
```

### Export Dashboard Data

Use browser DevTools:
```javascript
// Console:
copy(JSON.stringify(window.__phoenix_data__))
```

### Monitor Multiple Projects

```bash
# Terminal tabs or panes
# Tab 1:
watch -c -n 2 './launch.sh status'

# Tab 2:
./launch.sh logs v0-ipod

# Tab 3:
./launch.sh logs mymind-clone-web

# Tab 4:
./launch.sh logs recap
```

## Best Practices

1. **Always check status first** - `./launch.sh status` before monitoring
2. **Use tmux for deep dives** - When debugging or watching specific agent
3. **Use dashboard for overview** - When monitoring multiple agents
4. **Watch logs for errors** - Critical for troubleshooting
5. **Check Linear for context** - Agent's plan and reasoning
6. **Monitor workspace for changes** - Actual code modifications

## Resources

- **Symphony Docs**: Check repository README
- **Phoenix LiveView**: https://hexdocs.pm/phoenix_live_view
- **tmux Cheatsheet**: `man tmux` or online guides
- **Linear API**: https://developers.linear.app

## Feedback

If you encounter issues with monitoring tools:
1. Check script permissions: `chmod +x *.sh`
2. Verify dependencies: tmux, watch, python3, curl
3. Check log files for errors
4. Report issues to Symphony maintainers
