#!/usr/bin/env bash
# watch-workspace.sh - Monitor agent workspace activity

PROJECT=$1
WORKSPACE_ROOT="/Users/s3nik/Desktop/symphony-setup/workspaces"

if [ -z "$PROJECT" ]; then
    echo "Usage: $0 <project-name>"
    exit 1
fi

# Find active workspace (most recent directory)
ACTIVE_WORKSPACE=$(find "$WORKSPACE_ROOT/$PROJECT" -type d -maxdepth 1 -mindepth 1 2>/dev/null | sort -r | head -1)

if [ -z "$ACTIVE_WORKSPACE" ]; then
    echo "════════════════════════════════════════"
    echo "📁 No active workspace found for $PROJECT"
    echo "════════════════════════════════════════"
    exit 0
fi

# Header
echo "════════════════════════════════════════"
echo "📁 Workspace: $(basename $ACTIVE_WORKSPACE)"
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
RECENT=$(find . -type f -not -path './.git/*' -not -path './node_modules/*' -not -path './dist/*' -not -path './build/*' 2>/dev/null | \
    xargs ls -lt 2>/dev/null | head -10 | awk '{print $9}')
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
FILE_COUNT=$(find . -type f -not -path './.git/*' -not -path './node_modules/*' 2>/dev/null | wc -l | tr -d ' ')
TOTAL_SIZE=$(du -sh . 2>/dev/null | cut -f1)
echo "  Files: $FILE_COUNT"
echo "  Size: $TOTAL_SIZE"
