#!/usr/bin/env bash
# linear-audit.sh - Audit configured Linear projects for queue hygiene.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/projects.yml"
ENV_FILE="${SCRIPT_DIR}/.env.local"

if [ -f "${ENV_FILE}" ]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

if [ -z "${LINEAR_API_KEY:-}" ]; then
    echo "Error: LINEAR_API_KEY is not set. Add it to ${ENV_FILE}." >&2
    exit 1
fi

CONFIG_FILE="${CONFIG_FILE}" python3 - "$@" <<'PYTHON_SCRIPT'
import argparse
import json
import os
import sys
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import yaml

LINEAR_API_URL = "https://api.linear.app/graphql"
ACTIVE_STATES = {"Todo", "In Progress", "Rework", "Human Review", "Merging"}
REVIEW_STATES = {"Human Review", "Merging"}

QUERY = """
query($projectId: String!, $first: Int!, $after: String) {
  project(id: $projectId) {
    name
    issues(first: $first, after: $after, orderBy: updatedAt) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        identifier
        title
        url
        updatedAt
        state { name type }
        assignee { name }
        labels { nodes { name } }
        attachments { nodes { title url } }
        comments(first: 25) {
          nodes {
            body
            createdAt
            updatedAt
          }
        }
      }
    }
  }
}
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description="Audit configured Linear projects for issue hygiene.")
    parser.add_argument("--project", help="Only audit a single configured project by name.")
    parser.add_argument("--stale-hours", type=float, default=24.0, help="Mark active issues older than this as stale.")
    parser.add_argument("--state", action="append", dest="states", help="Only include issues in these states.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON instead of a terminal report.")
    return parser.parse_args()


def load_config(config_path: Path) -> dict:
    with config_path.open() as handle:
        return yaml.safe_load(handle)


def linear_request(query: str, variables: dict, api_key: str) -> dict:
    payload = json.dumps({"query": query, "variables": variables}).encode()
    request = urllib.request.Request(
        LINEAR_API_URL,
        data=payload,
        headers={
            "Authorization": api_key,
            "Content-Type": "application/json",
        },
    )
    with urllib.request.urlopen(request, timeout=20) as response:
        data = json.load(response)

    if data.get("errors"):
        raise RuntimeError(data["errors"][0]["message"])
    return data["data"]


def fetch_project_issues(project_slug: str, api_key: str) -> tuple[str, list[dict]]:
    issues: list[dict] = []
    after = None
    project_name = project_slug

    while True:
        data = linear_request(
            QUERY,
            {"projectId": project_slug, "first": 100, "after": after},
            api_key,
        )
        project = data["project"]
        if project is None:
            raise RuntimeError(f"Linear project {project_slug} not found")

        project_name = project.get("name") or project_name
        issue_connection = project["issues"]
        issues.extend(issue_connection["nodes"])
        page_info = issue_connection["pageInfo"]
        if not page_info["hasNextPage"]:
            break
        after = page_info["endCursor"]

    return project_name, issues


def parse_timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def has_workpad(issue: dict) -> bool:
    comments = issue.get("comments", {}).get("nodes", [])
    return any("codex workpad" in (comment.get("body") or "").lower() for comment in comments)


def has_pr_attachment(issue: dict) -> bool:
    attachments = issue.get("attachments", {}).get("nodes", [])
    return any("/pull/" in (attachment.get("url") or "") for attachment in attachments)


def summarize_issue(issue: dict, stale_hours: float) -> dict:
    updated_at = parse_timestamp(issue["updatedAt"])
    age_hours = round((datetime.now(timezone.utc) - updated_at).total_seconds() / 3600, 1)
    state = issue["state"]["name"]
    attention: list[str] = []

    if state in ACTIVE_STATES and age_hours >= stale_hours:
        attention.append(f"stale>{stale_hours:g}h")
    if state in ACTIVE_STATES and not has_workpad(issue):
        attention.append("missing-workpad")
    if state in REVIEW_STATES and not has_pr_attachment(issue):
        attention.append("missing-pr")
    if state == "Todo" and age_hours >= stale_hours:
        attention.append(f"queued>{stale_hours:g}h")

    return {
        "identifier": issue["identifier"],
        "title": issue["title"],
        "state": state,
        "updatedAt": issue["updatedAt"],
        "ageHours": age_hours,
        "url": issue["url"],
        "assignee": (issue.get("assignee") or {}).get("name"),
        "labels": [label["name"] for label in issue.get("labels", {}).get("nodes", [])],
        "hasWorkpad": has_workpad(issue),
        "hasPRAttachment": has_pr_attachment(issue),
        "attention": attention,
    }


def filter_issues(issues: list[dict], requested_states: set[str] | None) -> list[dict]:
    if not requested_states:
        return issues
    return [issue for issue in issues if issue["state"] in requested_states]


def terminal_report(project_reports: list[dict], stale_hours: float) -> str:
    lines: list[str] = []
    lines.append("Symphony Linear Audit")
    lines.append(f"Generated: {datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')}")
    lines.append(f"Stale threshold: {stale_hours:g}h")
    lines.append("")

    for report in project_reports:
        counts = " | ".join(f"{state}:{count}" for state, count in sorted(report["counts"].items()))
        lines.append(f"{report['project']} ({report['linearName']})")
        lines.append(f"  Counts: {counts or 'no issues'}")

        if report["needsAttention"]:
            lines.append("  Needs attention:")
            for issue in report["needsAttention"]:
                tags = ", ".join(issue["attention"])
                lines.append(f"    - {issue['identifier']} [{issue['state']}] {issue['title']} ({issue['ageHours']}h, {tags})")
        else:
            lines.append("  Needs attention: none")

        for heading, key in [
            ("  Todo queue:", "todo"),
            ("  Triage inbox:", "triage"),
            ("  Human review:", "review"),
        ]:
            group = report[key]
            if not group:
                continue
            lines.append(heading)
            for issue in group:
                lines.append(f"    - {issue['identifier']} [{issue['state']}] {issue['title']} ({issue['ageHours']}h)")

        lines.append("")

    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    args = parse_args()
    config = load_config(Path(os.environ["CONFIG_FILE"]))
    api_key = os.environ["LINEAR_API_KEY"]
    requested_states = set(args.states or [])

    configured_projects = config["projects"]
    if args.project:
        configured_projects = [project for project in configured_projects if project["name"] == args.project]
        if not configured_projects:
            raise SystemExit(f"Configured project '{args.project}' not found")

    project_reports: list[dict] = []

    for project in configured_projects:
        linear_name, raw_issues = fetch_project_issues(project["linear_project_slug"], api_key)
        summarized = [summarize_issue(issue, args.stale_hours) for issue in raw_issues]
        summarized = filter_issues(summarized, requested_states)
        counts = Counter(issue["state"] for issue in summarized)
        needs_attention = [issue for issue in summarized if issue["attention"]]

        project_reports.append(
            {
                "project": project["name"],
                "linearName": linear_name,
                "counts": dict(sorted(counts.items())),
                "needsAttention": sorted(needs_attention, key=lambda item: (-len(item["attention"]), -item["ageHours"])),
                "todo": [issue for issue in summarized if issue["state"] == "Todo"],
                "triage": [issue for issue in summarized if issue["state"] == "Triage"],
                "review": [issue for issue in summarized if issue["state"] in REVIEW_STATES],
            }
        )

    if args.json:
        print(json.dumps(project_reports, indent=2))
    else:
        print(terminal_report(project_reports, args.stale_hours), end="")

    return 0


if __name__ == "__main__":
    sys.exit(main())
PYTHON_SCRIPT
