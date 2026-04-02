#!/usr/bin/env bash
# linear-issuefmt.sh - Canonical formatter and Todo-readiness linter for Linear issue bodies.

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

STDIN_CAPTURE=""
cleanup() {
    if [ -n "${STDIN_CAPTURE}" ] && [ -f "${STDIN_CAPTURE}" ]; then
        rm -f "${STDIN_CAPTURE}"
    fi
}
if [ ! -t 0 ]; then
    STDIN_CAPTURE="$(mktemp)"
    cat > "${STDIN_CAPTURE}"
    trap cleanup EXIT
fi

export CONFIG_FILE SCRIPT_DIR STDIN_CAPTURE
python3 - "$@" <<'PYTHON_SCRIPT'
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, os.environ["SCRIPT_DIR"])
from issue_signature import evaluate_issue_body, load_signature
from project_catalog import find_project, load_config

LINEAR_API_URL = "https://api.linear.app/graphql"

ISSUE_QUERY = """
query IssueFmtIssue($teamKey: String!, $issueNumber: Float!) {
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
      description
      url
      state {
        name
      }
      project {
        id
        name
      }
    }
  }
}
"""

UPDATE_ISSUE_MUTATION = """
mutation IssueFmtUpdate($id: String!, $input: IssueUpdateInput!) {
  issueUpdate(id: $id, input: $input) {
    success
    issue {
      id
      identifier
      title
      url
      state { name }
    }
  }
}
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="./linear-issuefmt.sh",
        description="Format or lint a Linear issue body against the canonical Symphony issue signature.",
    )
    parser.add_argument("--project", help="Configured project name from projects.yml. Required with --issue.")
    parser.add_argument("--issue", help="Existing Linear issue identifier to format or lint.")
    parser.add_argument("--body-file", help="Path to a local Markdown body to format or lint.")
    parser.add_argument("--apply", action="store_true", help="Update the existing Linear issue description in-place.")
    parser.add_argument("--check", action="store_true", help="Exit non-zero if formatting changes are needed or the issue is not Todo-ready.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    return parser.parse_args()

def graphql(query: str, variables: dict) -> dict:
    api_key = os.environ.get("LINEAR_API_KEY", "").strip()
    if not api_key:
        raise RuntimeError("LINEAR_API_KEY is not set.")
    payload = json.dumps({"query": query, "variables": variables}).encode()
    request = urllib.request.Request(
        LINEAR_API_URL,
        data=payload,
        headers={"Authorization": api_key, "Content-Type": "application/json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = json.load(response)
    except urllib.error.HTTPError as exc:
        body = exc.read().decode("utf-8", errors="replace")
        raise RuntimeError(f"Linear API error ({exc.code}): {body}") from exc
    if data.get("errors"):
        raise RuntimeError(data["errors"][0]["message"])
    return data["data"]


def split_issue_identifier(identifier: str) -> tuple[str, int]:
    try:
        team_key, issue_number = identifier.rsplit("-", 1)
        return team_key, int(issue_number)
    except ValueError as exc:
        raise SystemExit(f"Invalid issue identifier '{identifier}'. Expected TEAM-123.") from exc


def fetch_issue(identifier: str) -> dict:
    team_key, issue_number = split_issue_identifier(identifier)
    data = graphql(ISSUE_QUERY, {"teamKey": team_key, "issueNumber": issue_number})
    nodes = data.get("issues", {}).get("nodes", [])
    if not nodes:
        raise SystemExit(f"Linear issue '{identifier}' was not found.")
    return nodes[0]


def update_issue(issue_id: str, description: str) -> dict:
    data = graphql(UPDATE_ISSUE_MUTATION, {"id": issue_id, "input": {"description": description}})
    result = data.get("issueUpdate", {})
    if result.get("success") is not True:
        raise RuntimeError("issueUpdate returned success=false")
    return result["issue"]


def read_body(args: argparse.Namespace) -> tuple[str, str, dict | None]:
    if args.issue and args.body_file:
        raise SystemExit("Use either --issue or --body-file, not both.")
    if args.apply and not args.issue:
        raise SystemExit("--apply is only supported with --issue.")
    if args.issue:
        issue = fetch_issue(args.issue)
        return issue.get("description") or "", "issue", issue
    if args.body_file:
        return Path(args.body_file).read_text(encoding="utf-8"), "body-file", None
    stdin_capture = os.environ.get("STDIN_CAPTURE", "").strip()
    if stdin_capture:
        return Path(stdin_capture).read_text(encoding="utf-8"), "stdin", None
    raise SystemExit("Provide --issue, --body-file, or pipe a body on stdin.")


def terminal_preview(report: dict) -> str:
    lines = [
        "Symphony Issue Signature",
        f"Input mode: {report['inputMode']}",
        f"Ready for Todo: {'yes' if report['signature']['readyForTodo'] else 'no'}",
        f"Needs formatting: {'yes' if report['signature']['needsFormatting'] else 'no'}",
    ]
    if report["identifier"]:
        lines.append(f"Issue: {report['identifier']}")
        lines.append(f"State: {report['state']}")
    summary = report["signature"]["summary"]
    if summary and summary != "ready":
        lines.append(f"Summary: {summary}")
    lines.extend(["", report["formattedBody"].rstrip()])
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    args = parse_args()
    config = load_config(Path(os.environ["CONFIG_FILE"]))
    project = find_project(config, args.project) if args.project else None
    if args.project and not project:
        raise SystemExit(f"Configured project '{args.project}' not found in {os.environ['CONFIG_FILE']}")
    signature = load_signature(Path(os.environ["SCRIPT_DIR"]) / "issue-signature.yml")
    body, input_mode, issue = read_body(args)

    signature_report = evaluate_issue_body(body, signature)
    applied = None
    if args.apply and issue and signature_report["needsFormatting"]:
        applied = update_issue(issue["id"], signature_report["formattedBody"])

    report = {
        "project": project["name"] if project else None,
        "identifier": (issue or {}).get("identifier"),
        "title": (issue or {}).get("title"),
        "state": ((issue or {}).get("state") or {}).get("name"),
        "url": (issue or {}).get("url"),
        "inputMode": input_mode,
        "signature": {key: value for key, value in signature_report.items() if key != "formattedBody"},
        "formattedBody": signature_report["formattedBody"],
        "applied": applied,
    }

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(terminal_preview(report), end="")

    if args.check and (signature_report["needsFormatting"] or not signature_report["readyForTodo"]):
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYTHON_SCRIPT
