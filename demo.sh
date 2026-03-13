#!/usr/bin/env bash
# demo.sh - Quick Symphony monitoring demo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

PROJECT=${1:-v0-ipod}

echo "🎬 Symphony Monitoring Demo"
echo "═══════════════════════════════════════"
echo

# Check if Symphony is running
echo "📊 Current Status:"
./launch.sh status
echo

# Get available issues
echo "Available monitoring targets:"
echo "  Project: $PROJECT"
echo "  Dashboard: http://localhost:4001"
echo

# Open web dashboard
echo "🌐 Opening web dashboard in browser..."
open http://localhost:4001
sleep 1

# Provide options
echo
echo "Choose your monitoring experience:"
echo
echo "1) Multi-pane terminal view (tmux)"
echo "2) Simple log watching"
echo "3) Status monitoring"
echo "4) Workspace file monitoring"
echo "5) Linear issue monitoring"
echo "6) Event highlighter"
echo "7) Just the web dashboard (already open)"
echo

read -p "Enter choice (1-7): " choice

case $choice in
    1)
        echo "🖥️  Launching multi-pane monitoring..."
        read -p "Enter issue ID (default: CRE-5): " issue_id
        issue_id=${issue_id:-CRE-5}
        ./watch-demo.sh "$PROJECT" "$issue_id"
        ;;
    2)
        echo "📜 Tailing logs..."
        ./launch.sh logs "$PROJECT"
        ;;
    3)
        echo "📊 Watching status..."
        if command -v watch &> /dev/null; then
            watch -c -n 2 './launch.sh status'
        else
            echo "❌ watch command not found. Install with: brew install watch"
            echo "Falling back to simple loop..."
            while true; do
                clear
                ./launch.sh status
                sleep 2
            done
        fi
        ;;
    4)
        echo "📁 Watching workspace..."
        if command -v watch &> /dev/null; then
            watch -c -n 3 "./watch-workspace.sh $PROJECT"
        else
            echo "❌ watch command not found. Install with: brew install watch"
            echo "Falling back to simple loop..."
            while true; do
                clear
                ./watch-workspace.sh "$PROJECT"
                sleep 3
            done
        fi
        ;;
    5)
        echo "🎫 Watching Linear issue..."
        read -p "Enter issue ID (e.g., CRE-5): " issue_id
        if [ -z "$issue_id" ]; then
            echo "❌ Issue ID required"
            exit 1
        fi
        if command -v watch &> /dev/null; then
            watch -c -n 5 "./watch-linear.sh $issue_id"
        else
            echo "❌ watch command not found. Install with: brew install watch"
            echo "Falling back to simple loop..."
            while true; do
                clear
                ./watch-linear.sh "$issue_id"
                sleep 5
            done
        fi
        ;;
    6)
        echo "🔍 Highlighting events..."
        ./watch-events.sh "$PROJECT"
        ;;
    7)
        echo "✅ Dashboard is open at http://localhost:4001"
        echo "   Enjoy watching your agents work!"
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac
