#!/usr/bin/env bash
# demo.sh - Quick Symphony monitoring demo

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

cd "$SCRIPT_DIR"
SYMPHONY_CONFIG_FILE="${SCRIPT_DIR}/projects.yml"

PROJECT=${1:-v0-ipod}
PROJECT_PORT="$(symphony_project_port "${PROJECT}")"
PROJECT_DASHBOARD_URL="http://localhost:${PROJECT_PORT}"

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
echo "  Dashboard: ${PROJECT_DASHBOARD_URL}"
echo

# Open web dashboard
echo "🌐 Opening web dashboard in browser..."
open "${PROJECT_DASHBOARD_URL}"
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
        echo "✅ Dashboard is open at ${PROJECT_DASHBOARD_URL}"
        echo "   Enjoy watching your agents work!"
        ;;
    *)
        echo "❌ Invalid choice"
        exit 1
        ;;
esac
