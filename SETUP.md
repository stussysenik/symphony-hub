# Setup Guide

Complete setup instructions for Symphony Hub.

---

## Prerequisites Checklist

Before you begin, ensure you have:

- [ ] **macOS or Linux** (tested on macOS, should work on Linux)
- [ ] **Symphony installed** and configured
- [ ] **Linear account** with API access
- [ ] **Git** installed
- [ ] **Python 3** installed (for JSON parsing)
- [ ] **Terminal** access
- [ ] **Local checkout of each product repo** you want Symphony to manage with worktrees
- [ ] **Node.js 24+** installed (for semantic-release tooling)

---

## Step 1: Clone the Repository

```bash
# Clone the repository
git clone https://github.com/stussysenik/symphony-hub.git
cd symphony-hub

# Or if you already have the files, just navigate there
cd /path/to/symphony-hub
```

---

## Step 2: Install Dependencies

### macOS

```bash
# Install tmux (terminal multiplexer for multi-pane view)
brew install tmux

# Install watch (for auto-refreshing displays)
brew install watch

# Verify installations
tmux -V      # Should show tmux version
watch --version  # Should show watch version
python3 --version  # Should show Python 3.x
node -v      # Should show Node 24+
```

### Linux (Ubuntu/Debian)

```bash
# Install tmux
sudo apt-get update
sudo apt-get install tmux

# Install watch (usually pre-installed)
sudo apt-get install procps

# Verify installations
tmux -V
watch --version
python3 --version
node -v
```

### Linux (RHEL/CentOS/Fedora)

```bash
# Install tmux
sudo yum install tmux

# Install watch
sudo yum install procps-ng

# Verify installations
tmux -V
watch --version
python3 --version
node -v
```

---

## Step 3: Configure Linear API Key

### Get Your Linear API Key

1. Go to https://linear.app/settings/api
2. Click "Create new personal API key"
3. Give it a name (e.g., "Symphony Monitoring")
4. Copy the generated key

### Add Key to Configuration

```bash
# Copy the example template
cp .env.local.example .env.local

# Edit the file
nano .env.local
# OR
vim .env.local
# OR
code .env.local  # If using VS Code
```

**In `.env.local`, replace the placeholder:**

```bash
# Before:
LINEAR_API_KEY=your_linear_api_key_here

# After:
LINEAR_API_KEY=lin_api_YOUR_ACTUAL_KEY_HERE
```

**Save and close the file.**

### Verify Configuration

```bash
# Check that .env.local exists and has your key
cat .env.local

# Should show:
# LINEAR_API_KEY=lin_api_...

# Verify it's not in Git (should show nothing)
git status | grep .env.local
```

**Important:** `.env.local` should **NEVER** appear in `git status`. If it does, check your `.gitignore` file.

---

## Step 4: Make Scripts Executable

```bash
# Make all shell scripts executable
chmod +x *.sh

# Verify
ls -l *.sh
# All should show -rwxr-xr-x (executable)
```

---

## Step 5: Configure Symphony (If Not Already Done)

### Check `projects.yml`

```bash
cat projects.yml
```

Should contain your project configuration. Example:

```yaml
workspace_root: "/Users/you/Desktop/symphony-hub/workspaces"
logs_root: "/Users/you/Desktop/symphony-hub/logs"
engine:
  repo_root: "/Users/you/Desktop/open-ai-symphony/symphony"
  fork_url: "https://github.com/you/symphony.git"
  upstream_url: "https://github.com/openai/symphony.git"
  expected_branch: "main"

projects:
  - name: "mymind-clone-web"
    github_url: "https://github.com/you/mymind-clone-web.git"
    repo_root: "/Users/you/Desktop/mymind-clone-web"
    linear_project_slug: "372637c999d1"
    max_agents: 2
    default_branch: "main"
    workspace_strategy: "worktree"
    workflow_appendix: "workflow-instructions/mymind-clone-web.md"
    assets:
      collect_attachments: true
      scan_project_dirs: true
      capture_screenshots: false
      supported_formats: [png, jpg, gif, webp, svg, figma]
```

After editing `projects.yml`, regenerate the per-project workflow files:

```bash
./generate-workflows.sh
```

### Verify Symphony is Running

```bash
# Check Symphony status
./launch.sh brief
./launch.sh status
./launch.sh sources

# If not running, start it
./launch.sh start

# Check Phoenix dashboard
# Should be accessible at http://localhost:4001
```

`./launch.sh brief` is the canonical startup/resume command. It combines the
health check, runtime summary, topology, latest checkpoint, and queue audit.

---

## Step 6: Test the Setup

### Test 1: Verify Scripts Work

```bash
# Test the operator entrypoint
./launch.sh brief

# Should show:
# - health
# - runtime status
# - topology
# - latest checkpoint summary
# - queue audit
```

Press `Ctrl+C` to exit if the queue section is still running.

### Test 2: Test Linear Connection

```bash
# Test Linear API connection (replace CRE-5 with your issue ID)
./watch-linear.sh CRE-5

# Should show issue details or error message
# Press Ctrl+C to exit
```

### Test 3: Test tmux Dashboard

```bash
# Test full monitoring dashboard
./watch-demo.sh

# Should open 4-pane tmux view
# To exit: Ctrl+B then type :kill-session
```

---

## Step 7: Verify Git Configuration

### Check .gitignore Protection

```bash
# Check that secrets are protected
git status

# Should NOT show:
# - .env.local
# - logs/
# - pids/
# - workspaces/

# Should show (if uncommitted):
# - README.md
# - SETUP.md
# - *.sh scripts
# - .env.local.example
```

### Verify No Secrets in Git

```bash
# Double-check .env.local is ignored
git check-ignore .env.local

# Should output: .env.local
# (Means it's properly ignored)
```

---

## Common Issues & Solutions

### Issue: `tmux: command not found`

**Solution:**
```bash
# macOS
brew install tmux

# Linux
sudo apt-get install tmux
```

### Issue: `watch: command not found`

**Solution:**
```bash
# macOS
brew install watch

# Linux
sudo apt-get install procps
```

### Issue: Scripts not executable

**Solution:**
```bash
chmod +x *.sh
```

### Issue: Phoenix dashboard not loading (http://localhost:4001)

**Solution:**
```bash
# Check if Symphony is running
./launch.sh status

# Start Symphony
./launch.sh start all

# Wait a few seconds, then try again
open http://localhost:4001
```

### Issue: Linear API errors

**Possible causes:**
1. Invalid API key
2. API key not set in `.env.local`
3. Linear permissions issue

**Solution:**
```bash
# 1. Verify .env.local exists
cat .env.local

# 2. Get new API key from https://linear.app/settings/api

# 3. Update .env.local with new key
nano .env.local
```

### Issue: `.env.local` appears in `git status`

**Solution:**
```bash
# Check .gitignore exists
cat .gitignore

# Should contain:
# .env.local

# If not, add it
echo ".env.local" >> .gitignore

# Remove from Git cache if accidentally added
git rm --cached .env.local
```

### Issue: `watch-linear.sh` shows "Issue not found"

**Possible causes:**
1. Wrong issue ID format
2. Issue doesn't exist
3. Linear API key doesn't have access

**Solution:**
```bash
# Check issue ID format (should be TEAM-NUMBER)
# Example: CRE-5, ENG-123, etc.

# Verify issue exists in Linear
# Go to Linear and check issue URL

# Test with different issue
./watch-linear.sh YOUR-ISSUE-ID
```

---

## Verification Checklist

After setup, verify:

- [ ] `tmux -V` shows version
- [ ] `watch --version` shows version
- [ ] `python3 --version` shows version
- [ ] `.env.local` exists with your API key
- [ ] `.env.local` is **NOT** in `git status`
- [ ] All `*.sh` files are executable
- [ ] `./demo.sh` shows menu
- [ ] http://localhost:4001 loads Phoenix dashboard
- [ ] `./watch-linear.sh ISSUE-ID` shows issue details

---

## Next Steps

Once setup is complete:

1. **Read the guides:**
   - `README.md` - Overview and quick start
   - `LINEAR-WORKFLOW.md` - How to use Linear with Symphony
   - `MONITORING-README.md` - Monitoring tools reference
   - `DASHBOARD-GUIDE.md` - Phoenix dashboard guide

2. **Create a Linear issue:**
   - Go to your Linear project
   - Create a new issue
   - Watch Symphony pick it up and start an agent

3. **Launch monitoring:**
   ```bash
   # Option 1: Interactive menu
   ./demo.sh

   # Option 2: Full dashboard
   ./watch-demo.sh

   # Option 3: Monitor specific issue
   ./watch-linear.sh YOUR-ISSUE-ID
   ```

---

## Optional: Figma MCP Integration

Figma MCP lets agents query Figma designs directly for design tokens, component specs, and layout details.

### Setup

1. **Get a Figma access token** from https://www.figma.com/developers/api#access-tokens

2. **Add to `.env.local`:**
   ```bash
   FIGMA_ACCESS_TOKEN=your_figma_token_here
   ```

3. **Reference the MCP config** in your Codex or Claude configuration:
   ```bash
   # The MCP server config is at figma-mcp.json
   cat figma-mcp.json
   ```

4. **Verify** by checking the health output:
   ```bash
   ./launch.sh health
   ```

### What This Enables

- Agents can query Figma files for design tokens (colors, typography, spacing)
- Agents can inspect component structure and properties
- Agents can extract layout measurements from Figma frames
- Combined with vision (image attachments), agents get both visual and structured design data

---

## Optional: Go TUI Dashboard

The TUI provides a terminal-native monitoring dashboard as an alternative to Phoenix LiveView.

### Setup

1. **Install Go** (1.21+):
   ```bash
   brew install go
   ```

2. **Build the TUI:**
   ```bash
   cd tui && make build
   ```

3. **Run:**
   ```bash
   # Standalone
   ./launch.sh tui

   # Or start Symphony + TUI together
   ./launch.sh start --tui
   ```

---

## Getting Help

If you encounter issues not covered here:

1. **Check the documentation:**
   - Re-read this SETUP guide
   - Review README.md troubleshooting section
   - Check LINEAR-WORKFLOW.md for Linear-specific issues

2. **Verify configuration:**
   - Check `projects.yml` matches your Linear/GitHub setup
   - Verify `.env.local` has correct API key
   - Ensure Symphony is running

3. **Test components individually:**
   - Test Linear API with `watch-linear.sh`
   - Test tmux with `tmux new-session`
   - Test Symphony with `./launch.sh status`

---

**Setup complete?** → See [LINEAR-GOLDEN-RULE.md](LINEAR-GOLDEN-RULE.md) for a quick-start guide, or [LINEAR-WORKFLOW.md](LINEAR-WORKFLOW.md) for the complete workflow!
