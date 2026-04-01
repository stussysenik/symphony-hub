#!/usr/bin/env bash
# watch-linear.sh - Monitor a single Linear issue.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.local"
ISSUE_ID="${1:-}"

if [ -z "${ISSUE_ID}" ]; then
    echo "Usage: $0 <issue-id>" >&2
    exit 1
fi

if [ -f "${ENV_FILE}" ]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

if [ -z "${LINEAR_API_KEY:-}" ]; then
    echo "Error: LINEAR_API_KEY not found in ${ENV_FILE}" >&2
    exit 1
fi

QUERY='query($teamKey: String!, $issueNumber: Float!) {
  issues(
    first: 1
    filter: {
      team: { key: { eq: $teamKey } }
      number: { eq: $issueNumber }
    }
  ) {
    nodes {
      identifier
      title
      state { name }
      url
      assignee { name }
      labels { nodes { name } }
      attachments { nodes { url title } }
      comments(first: 20) {
        nodes {
          body
          createdAt
        }
      }
    }
  }
}'

PAYLOAD=$(QUERY="${QUERY}" ISSUE_ID="${ISSUE_ID}" python3 <<'PYSCRIPT'
import json
import os

issue_id = os.environ["ISSUE_ID"]
team_key, issue_number = issue_id.rsplit("-", 1)

print(json.dumps({
    "query": os.environ["QUERY"],
    "variables": {
        "teamKey": team_key,
        "issueNumber": int(issue_number),
    },
}))
PYSCRIPT
)

RESPONSE=$(curl -fsS -H "Authorization: ${LINEAR_API_KEY}" \
  -H "Content-Type: application/json" \
  -d "${PAYLOAD}" \
  https://api.linear.app/graphql)

export RESPONSE ISSUE_ID
python3 << 'PYSCRIPT'
import json
import os
import sys
from datetime import datetime

response_text = os.environ.get("RESPONSE", "{}")
target_issue_id = os.environ.get("ISSUE_ID", "")

try:
    data = json.loads(response_text)
except json.JSONDecodeError:
    print("Error: failed to parse Linear API response")
    sys.exit(1)

if data.get("errors"):
    print("Error:", data["errors"][0]["message"])
    sys.exit(1)

all_issues = data.get("data", {}).get("issues", {}).get("nodes", [])
issue = all_issues[0] if all_issues else None

if not issue:
    print(f"Issue '{target_issue_id}' not found")
    sys.exit(1)

print("═" * 60)
print(f"Issue: {issue.get('identifier', 'N/A')} - {issue.get('title', 'N/A')}")
print("═" * 60)
print()

state = issue.get("state", {}).get("name", "Unknown")
print(f"State: {state}")

assignee = issue.get("assignee")
if assignee:
    print(f"Assignee: {assignee.get('name', 'Unassigned')}")

labels = issue.get("labels", {}).get("nodes", [])
if labels:
    print(f"Labels: {', '.join(label['name'] for label in labels)}")

print(f"URL: {issue.get('url', 'N/A')}")
print()

attachments = issue.get("attachments", {}).get("nodes", [])
if attachments:
    print("Attachments:")
    for att in attachments:
        print(f"  - {att.get('title', 'Unnamed')}")
        print(f"    {att.get('url', '')}")
    print()

comments = issue.get("comments", {}).get("nodes", [])
workpad_comments = [c for c in comments if "codex workpad" in (c.get("body") or "").lower()]

if workpad_comments:
    workpad_comments.sort(key=lambda comment: comment.get("createdAt", ""), reverse=True)
    latest = workpad_comments[0]
    created = latest.get("createdAt", "")
    body = latest.get("body", "")

    try:
        dt = datetime.fromisoformat(created.replace("Z", "+00:00"))
        time_str = dt.strftime("%Y-%m-%d %H:%M:%S")
    except Exception:
        time_str = created

    print(f"Latest Workpad Update ({time_str}):")
    print("─" * 60)

    lines = body.split("\n")[:20]
    for line in lines:
        print(f"  {line}")

    if len(body.split("\n")) > 20:
        print("  ...")
        print(f"  (truncated, {len(body.split('\n'))} total lines)")
else:
    print("No workpad comments yet")
    if comments:
        print(f"({len(comments)} total comments, none from Codex)")

print()
print("═" * 60)
PYSCRIPT
