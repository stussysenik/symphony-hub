#!/usr/bin/env bash
# linear-diagnose.sh - Diagnose existing Linear issues against current repo state.

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

export CONFIG_FILE SCRIPT_DIR
python3 - "$@" <<'PYTHON_SCRIPT'
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

import yaml

LINEAR_API_URL = "https://api.linear.app/graphql"
DEFAULT_REPORT_ROOT = Path(os.environ["SCRIPT_DIR"]) / "diagnoses"
DEFAULT_STATES = ["Todo", "Backlog"]
DEFAULT_LIMIT = 5
DEFAULT_STALE_HOURS = 72.0
DEFAULT_CODEX_MODEL = "gpt-5.4-mini"
DEFAULT_CODEX_TIMEOUT_SECONDS = 18
REVIEW_DECISION_ORDER = {
    "rewrite_in_backlog": 0,
    "supersede_or_split": 1,
    "implemented_on_main": 2,
    "ready_for_todo": 3,
    "keep_todo": 4,
    "keep_backlog": 5,
    "unclear": 6,
}

PROJECT_QUERY = """
query DiagnoseProject($projectId: String!, $first: Int!, $after: String) {
  project(id: $projectId) {
    id
    name
    url
    teams {
      nodes {
        id
        key
        name
        states(first: 50) {
          nodes {
            id
            name
            type
          }
        }
      }
    }
    issues(first: $first, after: $after, orderBy: updatedAt) {
      pageInfo {
        hasNextPage
        endCursor
      }
      nodes {
        id
        identifier
        title
        description
        url
        updatedAt
        state { id name type }
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

UPDATE_ISSUE_MUTATION = """
mutation DiagnoseIssueUpdate($id: String!, $input: IssueUpdateInput!) {
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

COMMENT_CREATE_MUTATION = """
mutation DiagnoseCommentCreate($issueId: String!, $body: String!) {
  commentCreate(input: { issueId: $issueId, body: $body }) {
    success
  }
}
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="./linear-diagnose.sh",
        description="Diagnose existing Linear issues against current repo state."
    )
    parser.add_argument("--project", required=True, help="Configured project name from projects.yml.")
    parser.add_argument("--issue", action="append", dest="issues", help="Specific Linear issue identifier to diagnose. Repeatable.")
    parser.add_argument("--state", action="append", dest="states", help="Filter to these issue states. Defaults to Todo and Backlog.")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="Maximum issues to diagnose when not targeting specific identifiers.")
    parser.add_argument("--stale-hours", type=float, default=DEFAULT_STALE_HOURS, help="Treat older queued issues as stale for fallback heuristics.")
    parser.add_argument("--apply", action="store_true", help="Comment on issues and apply the suggested state change.")
    parser.add_argument("--no-fetch", action="store_true", help="Skip the one-time git fetch against origin/<default_branch> before diagnosis.")
    parser.add_argument("--model", help="Optional Codex model override.")
    parser.add_argument("--report-root", default=str(DEFAULT_REPORT_ROOT), help="Local diagnosis report directory root.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    return parser.parse_args()


def load_config(config_path: Path) -> dict:
    with config_path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def get_project(config: dict, project_name: str) -> dict:
    for project in config.get("projects", []):
        if project.get("name") == project_name:
            return project
    raise SystemExit(f"Configured project '{project_name}' not found in {os.environ['CONFIG_FILE']}")


def run_command(args: list[str], cwd: Path | None = None, check: bool = True, timeout: float | None = None) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=str(cwd) if cwd else None, check=check, text=True, capture_output=True, timeout=timeout)


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


def fetch_project_context(project_slug: str) -> dict:
    issues: list[dict] = []
    after = None
    project_context = None
    while True:
        data = graphql(PROJECT_QUERY, {"projectId": project_slug, "first": 100, "after": after})
        project = data.get("project")
        if project is None:
            raise RuntimeError(f"Linear project {project_slug} not found")
        if project_context is None:
            project_context = project
        issues.extend(project.get("issues", {}).get("nodes", []))
        page_info = project.get("issues", {}).get("pageInfo", {})
        if not page_info.get("hasNextPage"):
            break
        after = page_info.get("endCursor")

    assert project_context is not None
    project_context["issues"] = {"nodes": issues}
    teams = project_context.get("teams", {}).get("nodes", [])
    if not teams:
        raise RuntimeError(f"Linear project '{project_slug}' has no associated teams.")
    project_context["team"] = teams[0]
    return project_context


def parse_timestamp(value: str) -> datetime:
    return datetime.fromisoformat(value.replace("Z", "+00:00"))


def has_workpad(issue: dict) -> bool:
    comments = issue.get("comments", {}).get("nodes", [])
    return any("codex workpad" in (comment.get("body") or "").lower() for comment in comments)


def strip_markdown_noise(text: str) -> str:
    cleaned = text or ""
    cleaned = re.sub(r"!\[[^\]]*\]\([^)]+\)", "", cleaned)
    cleaned = re.sub(r"\[([^\]]+)\]\([^)]+\)", r"\1", cleaned)
    cleaned = re.sub(r"`{1,3}", "", cleaned)
    cleaned = re.sub(r"\n{3,}", "\n\n", cleaned)
    return cleaned.strip()


def build_issue_task(issue: dict) -> str:
    description = strip_markdown_noise(issue.get("description") or "")
    attachments = issue.get("attachments", {}).get("nodes", [])
    parts = [issue["title"]]
    if description:
        parts.append(description[:2500])
    if attachments:
        lines = ["Attachments:"]
        for attachment in attachments[:5]:
            title = attachment.get("title") or "Untitled attachment"
            url = attachment.get("url") or ""
            lines.append(f"- {title}: {url}".rstrip(": "))
        parts.append("\n".join(lines))
    return "\n\n".join(part for part in parts if part).strip()


def run_intake(issue: dict, project_name: str, intake_root: Path) -> dict:
    cmd = [
        "bash",
        str(Path(os.environ["SCRIPT_DIR"]) / "linear-intake.sh"),
        "--project",
        project_name,
        "--issue",
        issue["identifier"],
        "--task",
        build_issue_task(issue),
        "--report-root",
        str(intake_root),
        "--skip-compile",
        "--no-fetch",
        "--json",
    ]
    result = run_command(cmd, check=False)
    if result.returncode != 0:
        raise RuntimeError(
            f"linear-intake failed for {issue['identifier']}.\n"
            f"stdout:\n{result.stdout}\n\nstderr:\n{result.stderr}"
        )
    return json.loads(result.stdout)


def summarize_code_evidence(hits: list[dict], limit: int = 8) -> list[str]:
    lines = []
    for hit in hits[:limit]:
        lines.append(f"- `{hit['path']}:{hit['line']}` ({hit['loc']} LOC) {hit['snippet'][:180].strip()}")
    return lines or ["- No code evidence captured."]


def summarize_related(issues: list[dict], limit: int = 5) -> list[str]:
    lines = []
    for issue in issues[:limit]:
        lines.append(f"- `{issue['identifier']}` [{issue['state']}] {issue['title']}")
    return lines or ["- No related issues were surfaced."]


def compile_with_codex(schema_path: Path, prompt: str, model: str | None) -> dict:
    if not shutil.which("codex"):
        raise RuntimeError("codex CLI is required for issue diagnosis compilation.")
    chosen_model = model or DEFAULT_CODEX_MODEL
    with tempfile.TemporaryDirectory() as temp_dir:
        with tempfile.NamedTemporaryFile("w+", suffix=".json", delete=False) as output_file:
            output_path = Path(output_file.name)
        cmd = [
            "codex",
            "exec",
            "-m",
            chosen_model,
            "-C",
            temp_dir,
            "--skip-git-repo-check",
            "-s",
            "read-only",
            "--output-schema",
            str(schema_path),
            "-o",
            str(output_path),
            "-",
        ]
        try:
            result = run_command(cmd, check=False, timeout=DEFAULT_CODEX_TIMEOUT_SECONDS)
            if result.returncode != 0:
                raise RuntimeError(
                    "Codex issue diagnosis failed.\n"
                    f"stdout:\n{result.stdout}\n\nstderr:\n{result.stderr}"
                )
            return json.loads(output_path.read_text(encoding="utf-8"))
        except subprocess.TimeoutExpired as exc:
            raise TimeoutError("Codex issue diagnosis timed out.") from exc
        finally:
            output_path.unlink(missing_ok=True)


def validate_payload(payload: dict) -> bool:
    required = ["decision", "suggested_state", "confidence", "operator_summary"]
    return all(str(payload.get(field, "")).strip() for field in required)


def feature_match(issue: dict, evidence_paths: list[str]) -> tuple[str | None, str | None]:
    title = issue["title"].lower()
    if "ascii" in title and any("ascii" in path for path in evidence_paths):
        return "implemented_on_main", "ASCII mode code surface already exists on current main."
    if ("3d" in title or "three" in title) and any("three" in path or "3d" in path for path in evidence_paths):
        return "implemented_on_main", "3D iPod code surface already exists on current main."
    if any(token in title for token in ["color", "colours", "palette", "lo-fi"]) and any(
        marker in path for path in evidence_paths for marker in ["grey-palette", "ipod-classic", "globals.css"]
    ):
        return "implemented_on_main", "Color and palette surfaces already exist on current main."
    if any(token in title for token in ["toolbar", "muted", "defaults"]) and any(
        marker in path for path in evidence_paths for marker in ["ipod-classic", "icon-button", "globals.css"]
    ):
        return "rewrite_in_backlog", "The toolbar surface exists, but the issue still needs a narrower UX spec."
    return None, None


def fallback_diagnosis(issue: dict, intake_output: dict, stale_hours: float) -> dict:
    current_state = issue["state"]["name"]
    age_hours = round((datetime.now(timezone.utc) - parse_timestamp(issue["updatedAt"])).total_seconds() / 3600, 1)
    evidence_hits = intake_output["diagnosis"]["codeEvidence"]
    evidence_paths = [hit["path"].lower() for hit in evidence_hits[:8]]
    workpad = has_workpad(issue)
    decision = "unclear"
    suggested_state = current_state
    confidence = "low"
    rationale = []

    matched_decision, matched_reason = feature_match(issue, evidence_paths)
    if matched_decision:
        decision = matched_decision
        suggested_state = "Backlog" if current_state == "Todo" else current_state
        confidence = "medium"
        rationale.append(matched_reason)
    elif current_state == "Todo" and age_hours >= stale_hours and not workpad:
        decision = "rewrite_in_backlog"
        suggested_state = "Backlog"
        confidence = "medium"
        rationale.append("The issue is stale in Todo and has no execution trail or workpad history.")
    elif current_state == "Backlog":
        decision = "keep_backlog"
        suggested_state = "Backlog"
        confidence = "low"
        rationale.append("The issue can remain in Backlog until it is rewritten into an agent-ready spec.")
    elif current_state == "Todo":
        decision = "keep_todo"
        suggested_state = "Todo"
        confidence = "low"
        rationale.append("No strong diagnosis signal was available, so the issue should stay visible for operator review.")

    if not rationale:
        rationale.append("Automatic diagnosis could not prove implementation status or a safer queue transition.")

    follow_up_title = issue["title"]
    follow_up_prompt = "Refresh this issue against current main, narrow the scope, and make acceptance criteria explicit."
    if decision == "implemented_on_main":
        follow_up_prompt = "Confirm whether the already-landed implementation is sufficient or whether a narrower polish follow-up should replace this issue."
    elif decision == "rewrite_in_backlog" and any(token in issue["title"].lower() for token in ["toolbar", "muted"]):
        follow_up_title = "Clarify toolbar affordances and active/default states"
        follow_up_prompt = "Rewrite this as a focused toolbar UX issue. Define what is confusing, which buttons/states are affected, and what validation should prove the toolbar is clearer."

    return {
        "decision": decision,
        "suggested_state": suggested_state,
        "confidence": confidence,
        "operator_summary": rationale[0],
        "rationale": rationale,
        "evidence": summarize_code_evidence(evidence_hits, limit=4),
        "follow_up_title": follow_up_title,
        "follow_up_prompt": follow_up_prompt,
    }


def build_prompt(project: dict, issue: dict, intake_output: dict, stale_hours: float) -> str:
    diagnosis = intake_output["diagnosis"]["gitDiagnosis"]
    age_hours = round((datetime.now(timezone.utc) - parse_timestamp(issue["updatedAt"])).total_seconds() / 3600, 1)
    description = strip_markdown_noise(issue.get("description") or "") or "(empty)"
    attachments = issue.get("attachments", {}).get("nodes", [])
    comments = issue.get("comments", {}).get("nodes", [])
    intake_config = project.get("intake", {})

    attachment_lines = [
        f"- {attachment.get('title') or 'Untitled'}: {attachment.get('url') or ''}".rstrip(": ")
        for attachment in attachments[:5]
    ] or ["- none"]
    notes_lines = [f"- {item}" for item in intake_config.get("notes", [])] or ["- none"]

    return "\n".join(
        [
            "You are diagnosing an existing Linear issue for Symphony Hub. You are not implementing code.",
            "",
            "Goal:",
            "- Determine whether the issue is already materially present on current main, still missing, too vague for execution, or should stay queued.",
            "- Choose the safest next queue state.",
            "- Be conservative: prefer Backlog over Todo when the issue is vague, stale, or lacks validation evidence.",
            "- Never suggest deleting history. Archive, supersede, or rewrite instead.",
            "- Do not suggest Done automatically. If the feature looks present on main but audit trail is missing, prefer Backlog with a follow-up note.",
            "",
            "Allowed decisions:",
            "- implemented_on_main",
            "- rewrite_in_backlog",
            "- ready_for_todo",
            "- keep_backlog",
            "- keep_todo",
            "- supersede_or_split",
            "- unclear",
            "",
            "Allowed suggested states:",
            "- Backlog",
            "- Triage",
            "- Todo",
            f"- {issue['state']['name']}",
            "",
            f"Project: {project['name']}",
            f"Repo root: {project['repo_root']}",
            f"Default branch: {project.get('default_branch', 'main')}",
            f"Required checks: {', '.join(intake_config.get('required_checks', [])) or 'none recorded'}",
            "Project notes:",
            *notes_lines,
            "",
            "Issue:",
            f"- Identifier: {issue['identifier']}",
            f"- Title: {issue['title']}",
            f"- Current state: {issue['state']['name']}",
            f"- Age: {age_hours} hours since last update",
            f"- Assignee: {(issue.get('assignee') or {}).get('name') or 'unassigned'}",
            f"- Has workpad: {'yes' if has_workpad(issue) else 'no'}",
            f"- Comment count: {len(comments)}",
            "Description:",
            description[:3500],
            "",
            "Attachments:",
            *attachment_lines,
            "",
            "Repo diagnosis:",
            f"- Current branch: {diagnosis.get('currentBranch') or 'detached HEAD'}",
            f"- Local {diagnosis['defaultBranch']}: {diagnosis.get('localDefaultSha') or 'unavailable'}",
            f"- origin/{diagnosis['defaultBranch']}: {diagnosis.get('remoteDefaultSha') or 'unavailable'}",
            f"- Ahead/behind: {diagnosis.get('aheadOfRemote')} ahead / {diagnosis.get('behindRemote')} behind",
            f"- Dirty state: {diagnosis['trackedDirty']} tracked / {diagnosis['untrackedDirty']} untracked",
            f"- Stale threshold for fallback: {stale_hours:g} hours",
            "",
            "Code evidence:",
            *summarize_code_evidence(intake_output["diagnosis"]["codeEvidence"]),
            "",
            "Authorization / restriction evidence:",
            *summarize_code_evidence(intake_output["diagnosis"]["authSignals"]),
            "",
            "Related Linear context:",
            *summarize_related(intake_output["diagnosis"]["relatedIssues"]),
            "",
            "Output requirements:",
            "- Return JSON only and follow the provided schema exactly.",
            "- operator_summary should be short and operator-facing.",
            "- rationale should explain the queue decision, not implementation details.",
            "- evidence should quote the most important file-level findings, not generic process advice.",
            "- Use Todo only if the issue looks narrow and immediately agent-ready on the evidence provided.",
            "- If the issue is already on main but likely needs polish, use implemented_on_main with Backlog and a rewrite-oriented follow-up.",
            "- Do not inspect the filesystem or run tools. Use only the supplied issue, repo diagnosis, and evidence.",
        ]
    )


def build_comment(issue: dict, diagnosis_result: dict, report_dir: Path) -> str:
    lines = [
        "## Diagnosis Review",
        "",
        f"- Reviewed against current `origin/main` on {datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%SZ')}.",
        f"- Decision: `{diagnosis_result['decision']}`",
        f"- Suggested state: `{diagnosis_result['suggested_state']}`",
        f"- Confidence: `{diagnosis_result['confidence']}`",
        f"- Summary: {diagnosis_result['operator_summary']}",
        f"- Local diagnosis bundle: `{report_dir}`",
        "",
        "### Rationale",
        *[f"- {item}" for item in diagnosis_result.get("rationale", [])],
        "",
        "### Evidence",
        *[f"- {item}" for item in diagnosis_result.get("evidence", [])],
    ]
    follow_up_title = diagnosis_result.get("follow_up_title", "").strip()
    follow_up_prompt = diagnosis_result.get("follow_up_prompt", "").strip()
    if follow_up_title or follow_up_prompt:
        lines.extend(
            [
                "",
                "### Suggested Follow-up",
                *(["- Title: " + follow_up_title] if follow_up_title else []),
                *(["- Prompt: " + follow_up_prompt] if follow_up_prompt else []),
            ]
        )
    lines.extend(
        [
            "",
            "- Preserve history. Rewrite, supersede, or reopen; do not delete.",
        ]
    )
    return "\n".join(lines)


def create_comment(issue_id: str, body: str) -> None:
    data = graphql(COMMENT_CREATE_MUTATION, {"issueId": issue_id, "body": body})
    if (data.get("commentCreate") or {}).get("success") is not True:
        raise RuntimeError("commentCreate returned success=false")


def resolve_state_id(states: list[dict], requested_state: str) -> tuple[str, str]:
    for state in states:
        if (state.get("name") or "").lower() == requested_state.lower():
            return state["id"], state["name"]
    if requested_state.lower() == "triage":
        for fallback in states:
            if (fallback.get("name") or "").lower() == "backlog":
                return fallback["id"], fallback["name"]
    raise RuntimeError(f"State '{requested_state}' not found on project team.")


def update_issue(issue: dict, team_states: list[dict], requested_state: str) -> tuple[dict, str]:
    state_id, resolved_state = resolve_state_id(team_states, requested_state)
    data = graphql(UPDATE_ISSUE_MUTATION, {"id": issue["id"], "input": {"stateId": state_id}})
    updated = data.get("issueUpdate", {})
    if updated.get("success") is not True:
        raise RuntimeError("issueUpdate returned success=false")
    return updated["issue"], resolved_state


def select_issues(project_context: dict, requested_identifiers: list[str], requested_states: set[str], limit: int) -> list[dict]:
    issues = project_context.get("issues", {}).get("nodes", [])
    if requested_identifiers:
        wanted = {item.upper() for item in requested_identifiers}
        selected = [issue for issue in issues if issue["identifier"].upper() in wanted]
        missing = sorted(wanted - {issue["identifier"].upper() for issue in selected})
        if missing:
            raise SystemExit(f"Issues not found in project: {', '.join(missing)}")
        return selected

    filtered = [issue for issue in issues if issue["state"]["name"] in requested_states]
    filtered.sort(key=lambda issue: issue["updatedAt"])
    return filtered[:limit]


def write_issue_bundle(issue_dir: Path, issue: dict, intake_output: dict, diagnosis_result: dict, comment: str, apply_result: dict | None) -> None:
    issue_dir.mkdir(parents=True, exist_ok=True)
    (issue_dir / "issue.json").write_text(json.dumps(issue, indent=2) + "\n", encoding="utf-8")
    (issue_dir / "intake.json").write_text(json.dumps(intake_output, indent=2) + "\n", encoding="utf-8")
    (issue_dir / "diagnosis.json").write_text(json.dumps(diagnosis_result, indent=2) + "\n", encoding="utf-8")
    (issue_dir / "comment.md").write_text(comment + "\n", encoding="utf-8")
    if apply_result is not None:
        (issue_dir / "apply-result.json").write_text(json.dumps(apply_result, indent=2) + "\n", encoding="utf-8")


def create_run_dir(report_root: Path, project_name: str) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    base = report_root / f"{timestamp}-{project_name}"
    candidate = base
    suffix = 1
    while candidate.exists():
        candidate = report_root / f"{timestamp}-{project_name}-{suffix}"
        suffix += 1
    candidate.mkdir(parents=True, exist_ok=False)
    return candidate


def preview(results: list[dict], report_dir: Path, apply: bool) -> None:
    print("Symphony Issue Diagnosis")
    print(f"Generated: {datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')}")
    print(f"Mode: {'apply' if apply else 'dry-run'}")
    print(f"Report bundle: {report_dir}")
    print()
    for result in results:
        print(f"{result['identifier']} [{result['currentState']}] -> {result['suggestedState']} ({result['decision']}, {result['confidence']})")
        print(f"  Summary: {result['operatorSummary']}")
        print(f"  Follow-up title: {result['followUpTitle'] or '(none)'}")
        if result["evidence"]:
            print("  Evidence:")
            for line in result["evidence"][:3]:
                print(f"    {line}")
        print()


def main() -> int:
    args = parse_args()
    config = load_config(Path(os.environ["CONFIG_FILE"]))
    project = get_project(config, args.project)
    repo_root = Path(project["repo_root"]).expanduser()
    if not repo_root.exists():
        raise SystemExit(f"Configured repo_root does not exist: {repo_root}")

    if not args.no_fetch:
        run_command(["git", "fetch", "--quiet", "origin", project.get("default_branch", "main"), "--prune"], cwd=repo_root, check=False)

    project_context = fetch_project_context(project["linear_project_slug"])
    target_issues = select_issues(project_context, args.issues or [], set(args.states or DEFAULT_STATES), args.limit)

    report_dir = Path(args.report_root).expanduser()
    report_dir.mkdir(parents=True, exist_ok=True)
    run_dir = create_run_dir(report_dir, project["name"])

    schema_path = Path(os.environ["SCRIPT_DIR"]) / "schemas" / "linear-diagnose-output.schema.json"
    team_states = project_context["team"].get("states", {}).get("nodes", [])
    results = []

    for issue in target_issues:
        issue_dir = run_dir / issue["identifier"]
        intake_output = run_intake(issue, project["name"], issue_dir / "intakes")
        try:
            diagnosis_result = compile_with_codex(
                schema_path=schema_path,
                prompt=build_prompt(project, issue, intake_output, args.stale_hours),
                model=args.model,
            )
            if not validate_payload(diagnosis_result):
                raise ValueError("Codex returned an incomplete diagnosis payload.")
            compile_mode = "codex"
        except (TimeoutError, ValueError, RuntimeError):
            diagnosis_result = fallback_diagnosis(issue, intake_output, args.stale_hours)
            compile_mode = "fallback"

        comment = build_comment(issue, diagnosis_result, issue_dir)
        apply_result = None
        resolved_state = diagnosis_result["suggested_state"]
        if args.apply:
            create_comment(issue["id"], comment)
            if diagnosis_result["suggested_state"] != issue["state"]["name"]:
                updated_issue, resolved_state = update_issue(issue, team_states, diagnosis_result["suggested_state"])
                apply_result = {"commented": True, "stateChanged": True, "updatedIssue": updated_issue, "resolvedState": resolved_state}
            else:
                apply_result = {"commented": True, "stateChanged": False, "resolvedState": resolved_state}

        write_issue_bundle(issue_dir, issue, intake_output, {**diagnosis_result, "compile_mode": compile_mode}, comment, apply_result)

        results.append(
            {
                "identifier": issue["identifier"],
                "title": issue["title"],
                "currentState": issue["state"]["name"],
                "decision": diagnosis_result["decision"],
                "confidence": diagnosis_result["confidence"],
                "operatorSummary": diagnosis_result["operator_summary"],
                "suggestedState": resolved_state,
                "followUpTitle": diagnosis_result.get("follow_up_title", ""),
                "followUpPrompt": diagnosis_result.get("follow_up_prompt", ""),
                "evidence": diagnosis_result.get("evidence", []),
                "compileMode": compile_mode,
                "reportDir": str(issue_dir),
                "applied": apply_result,
            }
        )

    results.sort(key=lambda item: (REVIEW_DECISION_ORDER.get(item["decision"], 99), item["identifier"]))
    output = {
        "project": project["name"],
        "reportDir": str(run_dir),
        "count": len(results),
        "results": results,
    }
    (run_dir / "summary.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")

    if args.json:
        print(json.dumps(output, indent=2))
        return 0

    preview(results, run_dir, args.apply)
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYTHON_SCRIPT
