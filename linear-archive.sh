#!/usr/bin/env bash
# linear-archive.sh - Archive explicit Linear issues without deleting history.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${SCRIPT_DIR}/.env.local"

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

TARGET_STATE="Backlog"
APPLY="false"
WORKSPACE_ROOT=""
REASON=""
ISSUES=()

usage() {
    cat <<'EOF'
Usage:
  ./linear-archive.sh [options] --issue CRE-8 [--issue CRE-9 ...]

Options:
  --issue <ID>            Linear issue identifier (repeatable)
  --state <NAME>          Target archive state name (default: Backlog)
  --workspace-root <DIR>  Optional workspace root for preserved local evidence
  --reason <TEXT>         Archive reason shown in the Linear comment
  --apply                 Execute comment + state change (default is dry-run)
  --help                  Show this help text

Examples:
  ./linear-archive.sh --issue CRE-8 --issue CRE-9
  ./linear-archive.sh --issue CRE-8 --state Cancelled --apply
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --issue)
            ISSUES+=("${2:-}")
            shift 2
            ;;
        --state)
            TARGET_STATE="${2:-}"
            shift 2
            ;;
        --workspace-root)
            WORKSPACE_ROOT="${2:-}"
            shift 2
            ;;
        --reason)
            REASON="${2:-}"
            shift 2
            ;;
        --apply)
            APPLY="true"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

if [ ${#ISSUES[@]} -eq 0 ]; then
    echo "Error: at least one --issue is required" >&2
    usage
    exit 1
fi

QUERY='query ArchiveIssueContext($teamKey: String!, $issueNumber: Float!) {
  issues(
    first: 1
    filter: {
      team: { key: { eq: $teamKey } }
      number: { eq: $issueNumber }
    }
  ) {
    nodes {
      id
      identifier
      title
      url
      state { id name type }
      team {
        key
        states(first: 50) {
          nodes {
            id
            name
            type
          }
        }
      }
    }
  }
}'

CREATE_COMMENT_MUTATION='mutation ArchiveAddComment($issueId: String!, $body: String!) {
  commentCreate(input: {issueId: $issueId, body: $body}) {
    success
  }
}'

UPDATE_STATE_MUTATION='mutation ArchiveIssue($issueId: String!, $stateId: String!) {
  issueUpdate(id: $issueId, input: {stateId: $stateId}) {
    success
  }
}'

ISSUES_JSON=$(printf '%s\n' "${ISSUES[@]}" | python3 -c 'import json,sys; print(json.dumps([line.strip() for line in sys.stdin if line.strip()]))')

export LINEAR_API_KEY QUERY CREATE_COMMENT_MUTATION UPDATE_STATE_MUTATION TARGET_STATE APPLY WORKSPACE_ROOT REASON ISSUES_JSON
python3 <<'PYSCRIPT'
import json
import os
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

LINEAR_API_URL = "https://api.linear.app/graphql"


def graphql(query: str, variables: dict) -> dict:
    payload = json.dumps({"query": query, "variables": variables}).encode()
    request = urllib.request.Request(
        LINEAR_API_URL,
        data=payload,
        headers={
            "Authorization": os.environ["LINEAR_API_KEY"],
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        data = json.load(response)

    if data.get("errors"):
        raise RuntimeError(data["errors"][0]["message"])
    return data["data"]


def fetch_issue(issue_identifier: str) -> dict:
    team_key, issue_number = issue_identifier.rsplit("-", 1)
    data = graphql(
        os.environ["QUERY"],
        {"teamKey": team_key, "issueNumber": int(issue_number)},
    )
    issues = data.get("issues", {}).get("nodes", [])
    if not issues:
        raise RuntimeError(f"{issue_identifier}: issue not found")
    return issues[0]


def resolve_state_id(issue: dict, state_name: str) -> str:
    states = issue.get("team", {}).get("states", {}).get("nodes", [])
    for state in states:
        if state.get("name") == state_name:
            return state["id"]
    raise RuntimeError(f"{issue['identifier']}: state '{state_name}' not found on team {issue.get('team', {}).get('key')}")


def build_comment(issue: dict, workspace_root: str, reason: str, target_state: str) -> str:
    timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ")
    workspace_path = Path(workspace_root, issue["identifier"]) if workspace_root else None
    lines = [
        "## Archive Note",
        "",
        f"- Archived from `{issue['state']['name']}` to `{target_state}` on {timestamp}.",
        "- This issue is being moved out of the active execution queue without deleting history.",
    ]

    if reason:
        lines.append(f"- Reason: {reason}")

    if workspace_path and workspace_path.exists():
        lines.append(f"- Preserved local workspace: `{workspace_path}`")

    lines.extend(
        [
            "- Revival path: refresh from current `main`, decide whether to supersede or reopen, then move back to `Todo` only when the spec is current.",
            "- History is intentionally preserved: issue thread, workpad, and local runtime artifacts remain available for audit.",
        ]
    )
    return "\n".join(lines)


def create_comment(issue_id: str, body: str) -> None:
    data = graphql(os.environ["CREATE_COMMENT_MUTATION"], {"issueId": issue_id, "body": body})
    if data.get("commentCreate", {}).get("success") is not True:
        raise RuntimeError(f"{issue_id}: commentCreate failed")


def update_state(issue_id: str, state_id: str) -> None:
    data = graphql(os.environ["UPDATE_STATE_MUTATION"], {"issueId": issue_id, "stateId": state_id})
    if data.get("issueUpdate", {}).get("success") is not True:
        raise RuntimeError(f"{issue_id}: issueUpdate failed")


target_state = os.environ["TARGET_STATE"]
apply_changes = os.environ["APPLY"].lower() == "true"
workspace_root = os.environ.get("WORKSPACE_ROOT", "").strip()
reason = os.environ.get("REASON", "").strip()
issues = json.loads(os.environ["ISSUES_JSON"])

results = []
for issue_identifier in issues:
    issue = fetch_issue(issue_identifier)
    state_id = resolve_state_id(issue, target_state)
    comment = build_comment(issue, workspace_root, reason, target_state)
    results.append(
        {
            "identifier": issue["identifier"],
            "title": issue["title"],
            "url": issue["url"],
            "fromState": issue["state"]["name"],
            "toState": target_state,
            "stateId": state_id,
            "comment": comment,
            "issueId": issue["id"],
        }
    )

if not apply_changes:
    print("Linear archive dry-run")
    print(f"Target state: {target_state}")
    print()
    for result in results:
        print(f"{result['identifier']} :: {result['title']}")
        print(f"  URL: {result['url']}")
        print(f"  Transition: {result['fromState']} -> {result['toState']}")
        print("  Comment preview:")
        for line in result["comment"].splitlines():
            print(f"    {line}")
        print()
    sys.exit(0)

for result in results:
    create_comment(result["issueId"], result["comment"])
    update_state(result["issueId"], result["stateId"])
    print(f"Archived {result['identifier']} -> {result['toState']}")
PYSCRIPT
