#!/usr/bin/env bash
# watch-workspace.sh - Monitor agent workspace activity

set -euo pipefail

PROJECT=${1:-}
ISSUE_ID=${2:-}
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

if [ -z "$PROJECT" ]; then
    echo "Usage: $0 <project-name> [issue-id]"
    exit 1
fi

WORKSPACE_ROOT="$(symphony_config_get "workspace_root")"

# Find the requested workspace or the most recently touched issue workspace for the project.
ACTIVE_WORKSPACE=$(PROJECT="${PROJECT}" ISSUE_ID="${ISSUE_ID}" WORKSPACE_ROOT="${WORKSPACE_ROOT}" python3 <<'PY'
import os
import sys

project = os.environ["PROJECT"]
issue_id = os.environ.get("ISSUE_ID", "")
workspace_root = os.environ["WORKSPACE_ROOT"]
project_root = os.path.join(workspace_root, project)

if not os.path.isdir(project_root):
    sys.exit(0)

if issue_id:
    issue_path = os.path.join(project_root, issue_id)
    if os.path.isdir(issue_path):
        print(issue_path)
    raise SystemExit(0)

candidates = []
for name in os.listdir(project_root):
    path = os.path.join(project_root, name)
    if os.path.isdir(path):
        candidates.append((os.path.getmtime(path), path))

if candidates:
    candidates.sort(reverse=True)
    print(candidates[0][1])
PY
)

if [ -z "$ACTIVE_WORKSPACE" ]; then
    echo "════════════════════════════════════════"
    echo "📁 No active workspace found for $PROJECT"
    echo "════════════════════════════════════════"
    exit 0
fi

# Header
echo "════════════════════════════════════════"
echo "📁 Workspace: $(basename "$ACTIVE_WORKSPACE")"
echo "════════════════════════════════════════"
echo

# Git status
cd "$ACTIVE_WORKSPACE"
echo "🔀 Git Branch:"
if git rev-parse --git-dir > /dev/null 2>&1; then
    git branch --show-current 2>/dev/null || echo "  (detached HEAD)"
else
    echo "  (not initialized)"
fi
echo

echo "📊 Git Status:"
if git rev-parse --git-dir > /dev/null 2>&1; then
    STATUS=$(git status -s 2>/dev/null)
    if [ -z "$STATUS" ]; then
        echo "  (clean)"
    else
        git status -s 2>/dev/null | head -20
    fi
else
    echo "  (not initialized)"
fi
echo

# Latest commits
echo "📝 Recent Commits:"
if git rev-parse --git-dir > /dev/null 2>&1; then
    COMMITS=$(git log --oneline --max-count=5 2>/dev/null)
    if [ -z "$COMMITS" ]; then
        echo "  (no commits yet)"
    else
        git log --oneline --max-count=5 2>/dev/null
    fi
else
    echo "  (no commits yet)"
fi
echo

# Recently modified files
echo "📄 Recently Modified (last 10):"
RECENT=$(python3 <<'PY'
import os

excluded = {".git", "node_modules", "dist", "build", ".next", ".turbo", "coverage"}
files = []

for dirpath, dirnames, filenames in os.walk("."):
    dirnames[:] = [d for d in dirnames if d not in excluded]
    for filename in filenames:
        path = os.path.join(dirpath, filename)
        try:
            files.append((os.path.getmtime(path), path))
        except OSError:
            continue

for _, path in sorted(files, reverse=True)[:10]:
    print(path)
PY
)
if [ -z "$RECENT" ]; then
    echo "  (none)"
else
    echo "$RECENT" | while read file; do
        if [ -n "$file" ]; then
            echo "  $file"
        fi
    done
fi
echo

# Workspace stats
echo "📈 Stats:"
FILE_COUNT=$(find . -type f \
    -not -path './.git/*' \
    -not -path './node_modules/*' \
    -not -path './.next/*' \
    -not -path './.turbo/*' \
    -not -path './coverage/*' \
    -not -path './dist/*' \
    -not -path './build/*' \
    2>/dev/null | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh . 2>/dev/null | cut -f1)
echo "  Files: $FILE_COUNT"
echo "  Size: $TOTAL_SIZE"
