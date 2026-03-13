#!/usr/bin/env bash
# watch-linear.sh - Monitor Linear issue status

ISSUE_ID=$1
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ -z "$ISSUE_ID" ]; then
    echo "Usage: $0 <issue-id>"
    exit 1
fi

# Extract API key from .env.local
LINEAR_API_KEY=$(grep LINEAR_API_KEY "$SCRIPT_DIR/.env.local" 2>/dev/null | cut -d'=' -f2 | tr -d '"' | tr -d "'" | tr -d ' ')

if [ -z "$LINEAR_API_KEY" ]; then
    echo "❌ Error: LINEAR_API_KEY not found in .env.local"
    exit 1
fi

# Simple GraphQL query - search all issues and filter client-side
# This is more reliable than complex filters
QUERY='query {
  issues(first: 250) {
    nodes {
      identifier
      title
      state { name }
      url
      assignee { name }
      labels { nodes { name } }
      attachments { nodes { url title } }
      comments(first: 10) {
        nodes {
          body
          createdAt
        }
      }
    }
  }
}'

# Query Linear API
RESPONSE=$(curl -s -H "Authorization: ${LINEAR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "{\"query\": $(printf '%s' "$QUERY" | python3 -c 'import json, sys; print(json.dumps(sys.stdin.read()))')}" \
  https://api.linear.app/graphql)

# Parse and display with Python
export RESPONSE
export ISSUE_ID
python3 << 'PYSCRIPT'
import sys
import json
import os
from datetime import datetime

response_text = os.environ.get('RESPONSE', '{}')
target_issue_id = os.environ.get('ISSUE_ID', '')

try:
    data = json.loads(response_text)
except json.JSONDecodeError:
    print("❌ Error: Failed to parse Linear API response")
    sys.exit(1)

if 'errors' in data:
    print("❌ Error:", data['errors'][0]['message'])
    sys.exit(1)

all_issues = data.get('data', {}).get('issues', {}).get('nodes', [])

# Find the target issue by identifier
issue = None
for i in all_issues:
    if i.get('identifier') == target_issue_id:
        issue = i
        break

if not issue:
    print(f"❌ Issue '{target_issue_id}' not found")
    print(f"   (searched {len(all_issues)} recent issues)")
    sys.exit(1)

# Header
print("═" * 60)
print(f"🎫 Issue: {issue.get('identifier', 'N/A')} - {issue.get('title', 'N/A')}")
print("═" * 60)
print()

# State (with emoji)
state = issue.get('state', {}).get('name', 'Unknown')
state_emoji = {
    'Todo': '⏸️ ',
    'In Progress': '⚡',
    'Human Review': '👀',
    'Merging': '🔀',
    'Done': '✅',
    'Rework': '🔄',
    'Backlog': '📋',
    'Canceled': '❌'
}.get(state, '📋')
print(f"{state_emoji}  State: {state}")

# Assignee
assignee = issue.get('assignee')
if assignee:
    print(f"👤 Assignee: {assignee.get('name', 'Unassigned')}")

# Labels
labels = issue.get('labels', {}).get('nodes', [])
if labels:
    label_names = ', '.join([l['name'] for l in labels])
    print(f"🏷️  Labels: {label_names}")

# URL
print(f"🔗 URL: {issue.get('url', 'N/A')}")
print()

# Attachments (PRs)
attachments = issue.get('attachments', {}).get('nodes', [])
if attachments:
    print("📎 Attachments:")
    for att in attachments:
        print(f"  • {att.get('title', 'Unnamed')}")
        print(f"    {att.get('url', '')}")
    print()

# Find workpad comments (comments containing "Codex Workpad")
comments = issue.get('comments', {}).get('nodes', [])
workpad_comments = [c for c in comments if 'Codex Workpad' in c.get('body', '') or 'codex workpad' in c.get('body', '').lower()]

if workpad_comments:
    latest = workpad_comments[0]
    created = latest.get('createdAt', '')
    body = latest.get('body', '')

    # Parse timestamp
    try:
        dt = datetime.fromisoformat(created.replace('Z', '+00:00'))
        time_str = dt.strftime('%Y-%m-%d %H:%M:%S')
    except:
        time_str = created

    print(f"💬 Latest Workpad Update ({time_str}):")
    print("─" * 60)

    # Show first 20 lines of workpad
    lines = body.split('\n')[:20]
    for line in lines:
        print(f"  {line}")

    if len(body.split('\n')) > 20:
        print("  ...")
        print(f"  (truncated, {len(body.split('\n'))} total lines)")
else:
    print("💬 No workpad comments yet")
    if comments:
        print(f"   ({len(comments)} total comments, none from Codex)")

print()
print("═" * 60)
PYSCRIPT
