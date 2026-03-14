# Linear Workflow Guide

Complete guide to using Linear with Symphony autonomous agents - how to start agents, check progress, and monitor work.

---

## Overview

Symphony integrates with Linear to create a **fully automated workflow**:

1. You capture an issue in Linear
2. Optional recommended intake: issue starts in `Triage`
3. You move the issue to `Todo` when it is ready for execution
4. Symphony detects it and starts an agent
5. Agent works autonomously
6. Agent posts updates to Linear
7. Agent creates PR and links it
8. You review and merge

The execution trigger is still `Todo`. If you want a lighter-weight intake flow, use `Triage` as your inbox and only move accepted work to `Todo`.

See [`LINEAR-INTAKE.md`](LINEAR-INTAKE.md) for the recommended setup.

---

## How Symphony Watches Linear

### Polling Mechanism

Symphony continuously polls your Linear project:

- **Frequency:** Every 5-10 seconds
- **What it watches:** Issues in "Todo" state
- **Project:** Configured in `projects.yml` (e.g., "Creative Playground")
- **Team:** Configured team prefix (e.g., "CRE")

`Triage` is safe to use as an inbox because Symphony does not start work from that state.

### Configuration

Check your `projects.yml`:

```yaml
projects:
  v0-ipod:
    linear:
      team: CRE                    # Team prefix
      project: Creative Playground  # Project name
```

Symphony watches for new issues in the "Creative Playground" project with "CRE" team prefix.

---

## Starting an Agent from Linear

### Step 1: Capture a Linear Issue

1. Go to your Linear workspace
2. Navigate to the configured project (e.g., "Creative Playground")
3. Click "New Issue" or press `C`
4. Recommended: start from a Linear form template
5. Fill in:
   - **Title:** Clear description of the task
   - **Description:** Detailed requirements (the more detail, the better)
   - **State:** Use **"Triage"** for intake, or **"Todo"** if ready to execute immediately
   - **Project:** Select the configured project

**Example:**
```
Title: Add dark mode toggle to settings page

Description:
Add a dark mode toggle switch to the settings page.
- Should persist user preference in localStorage
- Should apply theme immediately without page refresh
- Should follow the existing UI patterns
```

### Step 2: Move to Todo When Ready

If you created the issue in `Triage`, do a quick routing pass:

1. Confirm the project/team is correct
2. Add or accept labels
3. Attach any needed screenshots or mockups
4. Move the issue to `Todo`

### Step 3: Wait for Symphony to Detect It

Symphony will:
1. Poll Linear and detect the new issue
2. Check if it's in "Todo" state
3. Start an autonomous agent
4. Move issue to "In Progress"

**Timeline:** Usually 5-30 seconds

### Step 4: Agent Starts Working

The agent will:
1. Create workspace directory
2. Clone the GitHub repository
3. Install dependencies
4. Start working on the task
5. Post plan to Linear workpad

**No manual action needed!**

---

## Checking Progress in Linear

### Issue State Changes

Watch the issue state to see high-level progress:

| State | Emoji | Meaning |
|-------|-------|---------|
| **Triage** | 🧭 | New intake, being categorized |
| **Todo** | 📋 | Waiting for Symphony to pick up |
| **In Progress** | ⚡ | Agent actively working |
| **Human Review** | 👀 | Agent finished, PR ready for review |
| **Done** | ✅ | PR merged, issue complete |

### Workpad Comments

Agents post detailed updates to the Linear workpad:

#### Initial Plan Comment

When agent starts, it posts a plan:

```
🤖 Agent Plan

## Task Breakdown
- [ ] Create dark mode toggle component
- [ ] Add theme context
- [ ] Implement localStorage persistence
- [ ] Add CSS variables for theming
- [ ] Update settings page

## Environment
- Repository: ipod-shuffle
- Branch: feature/dark-mode-toggle
- Workspace: v0-ipod/CRE-5

## Progress
Starting work...
```

#### Progress Updates

As the agent works:

```
✅ Created theme context
✅ Implemented toggle component
⚡ Working on localStorage persistence...
```

#### Completion Comment

When finished:

```
✅ Task Complete

Created PR: #123
- Dark mode toggle added
- Theme persistence implemented
- Tests passing

Ready for review!
```

### PR Attachments

When the agent creates a PR, it:
1. Attaches the PR URL to the Linear issue
2. Changes issue state to "Human Review"
3. Waits for you to review and merge

**You'll see:**
- PR link in issue attachments
- State changed to "Human Review"
- Comment with PR details

---

## Monitoring Agent Work

### In Linear (Web)

**Best for:** Quick status checks, reviewing plans, finding PRs

1. Open your Linear workspace
2. Navigate to the issue
3. Check:
   - Current state (top right)
   - Workpad comments (detailed progress)
   - Attachments (PR links)

### With watch-linear.sh (Terminal)

**Best for:** Real-time monitoring, watching progress live

```bash
# Monitor specific issue (auto-refresh every 5 seconds)
./watch-linear.sh CRE-5

# Continuously watch
watch -c -n 5 './watch-linear.sh CRE-5'
```

**Shows:**
- Issue title and state (with emoji)
- Latest workpad comment
- PR attachments
- Assignee and labels
- Auto-refreshes every 5 seconds

### Full Dashboard (tmux)

**Best for:** Comprehensive monitoring, watching multiple aspects

```bash
# Launch 4-pane dashboard
./watch-demo.sh
```

**Shows:**
- **Top left:** Agent events (highlighted)
- **Top right:** Workspace git activity
- **Bottom left:** Raw agent logs
- **Bottom right:** Linear issue status

### Phoenix Web Dashboard

**Best for:** System overview, multiple agents, metrics

```bash
# Open dashboard
open http://localhost:4001
```

**Shows:**
- All active agents
- Task progress
- System metrics
- Event logs

See `DASHBOARD-GUIDE.md` for details.

---

## Complete Workflow Example

### Scenario: Add a New Feature

**Step 1: Create Linear Issue**

```
Title: Add user avatar upload

Description:
Allow users to upload custom avatars.
- Support PNG/JPG formats
- Max 2MB file size
- Crop to square aspect ratio
- Store in cloud storage

State: Todo
Project: Creative Playground
```

**Step 2: Monitor in Terminal**

```bash
# Launch monitoring
./watch-linear.sh CRE-5
```

**Step 3: Watch Progress**

You'll see the state change:

```
📋 Todo → ⚡ In Progress
```

Then workpad updates:

```
🤖 Agent started

Plan:
- [ ] Create upload component
- [ ] Add image cropping
- [ ] Implement cloud storage
- [ ] Add validation
- [ ] Write tests
```

```
✅ Upload component created
✅ Image cropping implemented
⚡ Working on cloud storage...
```

```
✅ All tasks complete
Created PR #42
Ready for review
```

State changes to:

```
⚡ In Progress → 👀 Human Review
```

**Step 4: Review PR**

Click PR link in Linear attachments → Review code → Merge

**Step 5: Mark Complete**

Change issue state to "Done" ✅

---

## Issue States Workflow Diagram

```
📋 Todo
  ↓
  Symphony detects issue
  ↓
⚡ In Progress
  ↓
  Agent works autonomously
  Agent posts updates to workpad
  ↓
  Agent creates PR
  ↓
👀 Human Review
  ↓
  You review and merge PR
  ↓
✅ Done
```

---

## Agent Updates in Linear

### What Gets Posted to Workpad

1. **Initial Plan**
   - Task breakdown with checkboxes
   - Environment information
   - Branch name

2. **Progress Updates**
   - Completed tasks ✅
   - Current work ⚡
   - Blockers ⚠️

3. **PR Creation**
   - PR URL
   - Summary of changes
   - Test status

### Comment Format

Agents use structured markdown:

```markdown
🤖 Agent Update

## Status
⚡ In Progress

## Completed
- ✅ Task 1
- ✅ Task 2

## Working On
- ⚡ Task 3

## Blockers
- ⚠️ None
```

---

## Advanced Monitoring

### Monitor Multiple Issues

```bash
# Terminal 1
./watch-linear.sh CRE-5

# Terminal 2
./watch-linear.sh CRE-6

# Terminal 3
./watch-linear.sh CRE-7
```

### Combine with Workspace Monitoring

```bash
# In tmux or split terminal:

# Pane 1: Linear issue
./watch-linear.sh CRE-5

# Pane 2: Workspace activity
./watch-workspace.sh v0-ipod

# Pane 3: Agent events
./watch-events.sh v0-ipod
```

### Use the Interactive Launcher

```bash
./demo.sh

# Options:
# 1. Open Phoenix Dashboard
# 2. Watch Full Demo
# 3. Monitor Workspace
# 4. Watch Events
# 5. Monitor Linear Issue  ← Select this
```

---

## Tips & Best Practices

### Writing Good Issue Descriptions

**Good:**
```
Title: Add search functionality to blog

Description:
Implement search with the following requirements:
- Full-text search across all blog posts
- Search by title, content, and tags
- Display results with highlights
- Add search box to navigation
- Use existing design system components
```

**Not as good:**
```
Title: Add search

Description:
Add search feature
```

**Why?** More detail = better agent understanding = better results

### Checking Progress Frequently

Use `watch` command for auto-refresh:

```bash
# Auto-refresh every 5 seconds
watch -c -n 5 './watch-linear.sh CRE-5'

# Auto-refresh every 10 seconds
watch -c -n 10 './watch-linear.sh CRE-5'
```

### Handling Blockers

If agent posts a blocker in workpad:

```
⚠️ Blocker: Missing API key for cloud storage
```

1. Resolve the blocker
2. Add clarification as Linear comment
3. Agent will continue when unblocked

### Multi-Agent Scenarios

If running multiple agents:

```bash
# Use full dashboard to monitor all
./watch-demo.sh

# Or use Phoenix dashboard
open http://localhost:4001
```

---

## Troubleshooting

### Issue: Agent not starting

**Possible causes:**
1. Issue not in "Todo" state
2. Wrong project in Linear
3. Symphony not running

**Solutions:**
```bash
# Check Symphony is running
./launch.sh status

# Check projects.yml configuration
cat projects.yml

# Verify issue is in correct project and "Todo" state
```

### Issue: No workpad updates

**Possible causes:**
1. Agent hasn't started yet
2. Linear API permissions issue
3. Network connectivity issue

**Solutions:**
```bash
# Check Linear API connection
./watch-linear.sh YOUR-ISSUE-ID

# Check agent logs
tail -f logs/v0-ipod.log

# Check Symphony dashboard
open http://localhost:4001
```

### Issue: PR not created

**Possible causes:**
1. Agent encountered error
2. GitHub permissions issue
3. Task incomplete

**Solutions:**
```bash
# Check agent logs for errors
tail -n 100 logs/v0-ipod.log

# Check workspace
cd workspaces/v0-ipod/YOUR-ISSUE-ID
git status

# Review workpad for error messages
```

---

## Quick Reference

### Starting Agents
1. Create Linear issue in configured project
2. Set state to "Todo"
3. Wait 5-30 seconds for Symphony to detect

### Checking Progress
```bash
# Quick check
./watch-linear.sh ISSUE-ID

# Full monitoring
./watch-demo.sh

# Web dashboard
open http://localhost:4001
```

### Issue States
- 📋 **Todo** - Waiting to start
- ⚡ **In Progress** - Agent working
- 👀 **Human Review** - PR ready
- ✅ **Done** - Complete

### Finding PR
1. Open Linear issue
2. Check attachments section
3. Click PR link

---

**Ready to start?** Create a Linear issue and watch the agent work! 🚀

See [MONITORING-README.md](MONITORING-README.md) for detailed monitoring tool usage.
