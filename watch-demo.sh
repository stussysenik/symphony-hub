#!/usr/bin/env bash
# watch-demo.sh - Multi-pane Symphony monitoring

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT=${1:-v0-ipod}
ISSUE_ID=${2:-CRE-5}

# Check if tmux is installed
if ! command -v tmux &> /dev/null; then
    echo "❌ tmux is not installed. Install with: brew install tmux"
    exit 1
fi

# Check if watch is installed
if ! command -v watch &> /dev/null; then
    echo "❌ watch is not installed. Install with: brew install watch"
    exit 1
fi

echo "🎬 Launching Symphony monitoring demo..."
echo "   Project: $PROJECT"
echo "   Issue: $ISSUE_ID"
echo

# Kill existing session if it exists
tmux kill-session -t symphony-demo 2>/dev/null || true

# Create new tmux session (detached)
tmux new-session -d -s symphony-demo -x "$(tput cols)" -y "$(tput lines)"

# Split into 4 panes
# First split vertically (left/right)
tmux split-window -h -t symphony-demo

# Split left pane horizontally (top-left/bottom-left)
tmux select-pane -t symphony-demo:0.0
tmux split-window -v

# Split right pane horizontally (top-right/bottom-right)
tmux select-pane -t symphony-demo:0.2
tmux split-window -v

# Pane 0 (top-left): Status dashboard
tmux select-pane -t symphony-demo:0.0
tmux send-keys "cd '$SCRIPT_DIR'" C-m
tmux send-keys "watch -c -n 2 './launch.sh status'" C-m

# Pane 1 (bottom-left): Workspace activity
tmux select-pane -t symphony-demo:0.1
tmux send-keys "cd '$SCRIPT_DIR'" C-m
tmux send-keys "watch -c -n 3 './watch-workspace.sh $PROJECT'" C-m

# Pane 2 (top-right): Live logs
tmux select-pane -t symphony-demo:0.2
tmux send-keys "cd '$SCRIPT_DIR'" C-m
tmux send-keys "./launch.sh logs $PROJECT" C-m

# Pane 3 (bottom-right): Linear status
tmux select-pane -t symphony-demo:0.3
tmux send-keys "cd '$SCRIPT_DIR'" C-m
tmux send-keys "watch -c -n 5 './watch-linear.sh $ISSUE_ID'" C-m

# Set pane titles
tmux select-pane -t symphony-demo:0.0 -T "Status"
tmux select-pane -t symphony-demo:0.1 -T "Workspace"
tmux select-pane -t symphony-demo:0.2 -T "Logs"
tmux select-pane -t symphony-demo:0.3 -T "Linear"

# Select first pane
tmux select-pane -t symphony-demo:0.0

echo "✅ Monitoring session created!"
echo
echo "   Ctrl+b → Arrow keys: Navigate between panes"
echo "   Ctrl+b d: Detach session"
echo "   tmux attach -t symphony-demo: Reattach"
echo "   tmux kill-session -t symphony-demo: Exit"
echo

# Attach to session
tmux attach-session -t symphony-demo
