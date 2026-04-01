#!/usr/bin/env bash
# watch-events.sh - Highlight interesting Symphony events

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"
PROJECT=${1:-v0-ipod}
LOGS_ROOT="$(symphony_config_get "logs_root")"
LOG_FILE="${LOGS_ROOT}/${PROJECT}.log"

if [ ! -f "$LOG_FILE" ]; then
    echo "❌ Log file not found: $LOG_FILE"
    exit 1
fi

echo "🔍 Watching key events for $PROJECT..."
echo "═══════════════════════════════════════"
echo

tail -f "$LOG_FILE" | while read line; do
    # Highlight commits
    if echo "$line" | grep -qi "commit"; then
        echo -e "\033[32m📝 COMMIT: $line\033[0m"

    # Highlight PR creation
    elif echo "$line" | grep -qi "pull.*request\|pr.*created"; then
        echo -e "\033[35m🔀 PR: $line\033[0m"

    # Highlight state changes
    elif echo "$line" | grep -qi "state.*changed\|moving.*to"; then
        echo -e "\033[33m🔄 STATE: $line\033[0m"

    # Highlight tool calls
    elif echo "$line" | grep -qi "tool.*call\|executing"; then
        echo -e "\033[34m🔧 TOOL: $line\033[0m"

    # Highlight errors
    elif echo "$line" | grep -qi "error\|failed"; then
        echo -e "\033[31m❌ ERROR: $line\033[0m"

    # Highlight agent events
    elif echo "$line" | grep -qi "turn.*completed\|reasoning\|item.*started"; then
        echo -e "\033[36m⚡ AGENT: $line\033[0m"
    fi
done
