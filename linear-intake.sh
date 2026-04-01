#!/usr/bin/env bash
# linear-intake.sh - Compile a natural-language task into a diagnosis-backed Linear issue draft.

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
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.error
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import yaml

sys.path.insert(0, os.environ["SCRIPT_DIR"])
from issue_signature import get_managed_block_markers, load_signature, render_signature_sections, upsert_managed_block as signature_upsert_managed_block

LINEAR_API_URL = "https://api.linear.app/graphql"
DEFAULT_REPORT_ROOT = Path(os.environ["SCRIPT_DIR"]) / "intakes"
DEFAULT_CONTEXT_ISSUES = 12
DEFAULT_CREATE_STATE = "Triage"
DEFAULT_CODEX_MODEL = "gpt-5.4-mini"
DEFAULT_CODEX_TIMEOUT_SECONDS = 20
SIGNATURE = load_signature(Path(os.environ["SCRIPT_DIR"]) / "issue-signature.yml")
MANAGED_BLOCK_START, MANAGED_BLOCK_END = get_managed_block_markers(SIGNATURE, "intake")
STOPWORDS = {
    "about", "after", "again", "against", "agent", "agents", "also", "always",
    "and", "another", "around", "because", "before", "being", "board", "both",
    "bring", "build", "built", "can", "clean", "could", "does", "done", "each",
    "easy", "ensure", "everything", "feel", "from", "going", "have", "here",
    "into", "issue", "issues", "just", "keep", "like", "main", "make", "must",
    "need", "next", "only", "onto", "over", "project", "really", "repo", "right",
    "should", "start", "still", "such", "that", "them", "there", "these", "they",
    "thing", "this", "those", "through", "todo", "want", "were", "what", "when",
    "with", "work", "would", "write", "your", "the", "desktop", "mobile", "state", "read",
    "current", "stale", "refresh", "explicit", "guardrails", "updated", "wording",
}
EXCLUDED_GLOBS = [
    "!node_modules/**",
    "!.next/**",
    "!dist/**",
    "!build/**",
    "!coverage/**",
    "!logs/**",
    "!pids/**",
    "!workspaces/**",
]
AUTH_PATTERNS = [
    ("authorization", r"\b(auth|authorize|authorization|permission|permissions|rbac|acl|role|roles|policy|policies|guard)\b"),
    ("identity-session", r"\b(session|jwt|token|oauth|clerk|nextauth|auth0|supabase)\b"),
    ("restriction", r"\b(protected|readonly|read-only|forbidden|deny|scope|scopes|admin)\b"),
]
PROJECT_CONTEXT_QUERY = """
query IntakeProjectContext($projectId: String!, $first: Int!) {
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
        labels(first: 100) {
          nodes {
            id
            name
          }
        }
      }
    }
    issues(first: $first, orderBy: updatedAt) {
      nodes {
        id
        identifier
        title
        url
        updatedAt
        state {
          name
          type
        }
      }
    }
  }
}
"""
PROJECT_CONTEXT_QUERY_NO_LABELS = """
query IntakeProjectContextNoLabels($projectId: String!, $first: Int!) {
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
    issues(first: $first, orderBy: updatedAt) {
      nodes {
        id
        identifier
        title
        url
        updatedAt
        state {
          name
          type
        }
      }
    }
  }
}
"""
ISSUE_QUERY = """
query IntakeIssueContext($teamKey: String!, $issueNumber: Float!) {
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
        id
        name
        type
      }
      project {
        id
        name
      }
    }
  }
}
"""
CREATE_ISSUE_MUTATION = """
mutation IntakeCreateIssue($input: IssueCreateInput!) {
  issueCreate(input: $input) {
    success
    issue {
      id
      identifier
      title
      url
      state {
        name
      }
    }
  }
}
"""
UPDATE_ISSUE_MUTATION = """
mutation IntakeUpdateIssue($id: String!, $input: IssueUpdateInput!) {
  issueUpdate(id: $id, input: $input) {
    success
    issue {
      id
      identifier
      title
      url
      state {
        name
      }
    }
  }
}
"""
COMMENT_CREATE_MUTATION = """
mutation IntakeCommentCreate($issueId: String!, $body: String!) {
  commentCreate(input: { issueId: $issueId, body: $body }) {
    success
  }
}
"""


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="./linear-intake.sh",
        description="Compile a natural-language task into a diagnosis-backed Linear intake draft."
    )
    parser.add_argument("--project", required=True, help="Configured project name from projects.yml.")
    parser.add_argument("--title", help="Optional title override.")
    parser.add_argument("--task", help="Natural-language task text.")
    parser.add_argument("--task-file", help="Path to a file containing the task.")
    parser.add_argument("--prompt", dest="task_legacy", help="Legacy alias for --task.")
    parser.add_argument("--prompt-file", dest="task_file_legacy", help="Legacy alias for --task-file.")
    parser.add_argument("--issue", help="Existing Linear issue identifier to refine instead of creating a new issue.")
    parser.add_argument("--status", default=DEFAULT_CREATE_STATE, help="State to apply on create; default Triage.")
    parser.add_argument("--apply", action="store_true", help="Create or update the issue in Linear.")
    parser.add_argument(
        "--apply-state",
        action="store_true",
        help="When refining an existing issue, also apply the resolved state change.",
    )
    parser.add_argument(
        "--labels",
        default="",
        help="Comma-separated label names to apply. On create, defaults to the compiled suggestions if omitted.",
    )
    parser.add_argument("--model", help="Optional Codex model override.")
    parser.add_argument("--skip-compile", action="store_true", help=argparse.SUPPRESS)
    parser.add_argument("--context-issues", type=int, default=DEFAULT_CONTEXT_ISSUES, help="How many recent project issues to inspect.")
    parser.add_argument("--related-limit", type=int, default=5, help="Maximum related Linear issues to include.")
    parser.add_argument("--evidence-limit", type=int, default=8, help="Maximum code evidence hits to include.")
    parser.add_argument("--auth-limit", type=int, default=6, help="Maximum auth/restriction hits to include.")
    parser.add_argument("--report-root", default=str(DEFAULT_REPORT_ROOT), help="Local report directory root.")
    parser.add_argument("--no-fetch", action="store_true", help="Skip git fetch against origin/<default_branch>.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    return parser.parse_args()


def load_task(args: argparse.Namespace) -> str:
    sources = [args.task, args.task_file, args.task_legacy, args.task_file_legacy]
    if sum(bool(item) for item in sources) > 1:
        raise SystemExit("Use only one of --task, --task-file, --prompt, or --prompt-file.")
    if args.task:
        return args.task.strip()
    if args.task_file:
        return Path(args.task_file).read_text(encoding="utf-8").strip()
    if args.task_legacy:
        return args.task_legacy.strip()
    if args.task_file_legacy:
        return Path(args.task_file_legacy).read_text(encoding="utf-8").strip()
    stdin_capture = os.environ.get("STDIN_CAPTURE", "").strip()
    if stdin_capture:
        return Path(stdin_capture).read_text(encoding="utf-8").strip()
    raise SystemExit("Provide --task, --task-file, or pipe task text on stdin.")


def load_config(config_path: Path) -> dict:
    with config_path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def get_project(config: dict, project_name: str) -> dict:
    for project in config.get("projects", []):
        if project.get("name") == project_name:
            return project
    raise SystemExit(f"Configured project '{project_name}' not found in {os.environ['CONFIG_FILE']}")


def run_command(args: list[str], cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, cwd=str(cwd) if cwd else None, check=check, text=True, capture_output=True)


def safe_git_output(repo_root: Path, *args: str) -> str:
    try:
        result = run_command(["git", *args], cwd=repo_root, check=True)
    except subprocess.CalledProcessError:
        return ""
    return result.stdout.strip()


def collect_git_diagnosis(repo_root: Path, default_branch: str, fetch: bool) -> dict:
    fetch_result = None
    if fetch:
        fetch_result = run_command(["git", "fetch", "--quiet", "origin", default_branch, "--prune"], cwd=repo_root, check=False)

    status_lines = safe_git_output(repo_root, "status", "--porcelain").splitlines()
    tracked_dirty = sum(1 for line in status_lines if line and not line.startswith("??"))
    untracked_dirty = sum(1 for line in status_lines if line.startswith("??"))
    current_branch = safe_git_output(repo_root, "branch", "--show-current")
    local_default_sha = safe_git_output(repo_root, "rev-parse", "--short", default_branch)
    remote_default_sha = safe_git_output(repo_root, "rev-parse", "--short", f"origin/{default_branch}")
    main_subject = safe_git_output(repo_root, "log", "--format=%s", "-1", f"origin/{default_branch}")
    recent_main = safe_git_output(repo_root, "log", "--oneline", "-5", f"origin/{default_branch}").splitlines()

    ahead = behind = None
    if local_default_sha and remote_default_sha:
        counts = safe_git_output(repo_root, "rev-list", "--left-right", "--count", f"{default_branch}...origin/{default_branch}")
        if counts:
            left, right = counts.split()
            ahead, behind = int(left), int(right)

    return {
        "fetched": fetch_result.returncode == 0 if fetch_result else True,
        "fetchError": fetch_result.stderr.strip() if fetch_result else "",
        "defaultBranch": default_branch,
        "currentBranch": current_branch or None,
        "localDefaultSha": local_default_sha or None,
        "remoteDefaultSha": remote_default_sha or None,
        "remoteDefaultSubject": main_subject or None,
        "recentRemoteCommits": recent_main,
        "aheadOfRemote": ahead,
        "behindRemote": behind,
        "trackedDirty": tracked_dirty,
        "untrackedDirty": untracked_dirty,
        "dirty": bool(tracked_dirty or untracked_dirty),
        "timestampUtc": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ"),
    }


def extract_keywords(text: str, limit: int = 10) -> list[str]:
    candidates = re.findall(r"[A-Za-z][A-Za-z0-9_-]{2,}", text.lower())
    ordered = []
    seen = set()
    for candidate in candidates:
        if candidate in STOPWORDS or candidate in seen or candidate.isdigit():
            continue
        seen.add(candidate)
        ordered.append(candidate)
        if len(ordered) >= limit:
            break
    return ordered


def file_loc(path: Path) -> int:
    try:
        with path.open(encoding="utf-8", errors="ignore") as handle:
            return sum(1 for _ in handle)
    except OSError:
        return 0


def is_markdown_path(path_text: str) -> bool:
    lower = path_text.lower()
    return lower.endswith(".md") or lower.endswith(".mdx")


def is_code_like_path(path_text: str) -> bool:
    lower = path_text.lower()
    return lower.endswith((".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".css", ".scss", ".swift", ".go"))


def path_priority(path_text: str) -> int:
    lower = path_text.lower()
    score = 0
    if is_code_like_path(path_text):
        score += 4
    if lower.startswith("apps/") or lower.startswith("packages/") or lower.startswith("extension") or lower.startswith("dspy-service/"):
        score += 2
    if is_markdown_path(path_text):
        score -= 3
    return score


def normalize_roots(repo_root: Path, writable_paths: list[str]) -> list[str]:
    roots = []
    for item in writable_paths:
        clean = item.strip("/").strip()
        if clean and (repo_root / clean).exists():
            roots.append(clean)
    return roots or ["."]


def build_excluded_globs(restricted_paths: list[str]) -> list[str]:
    patterns = list(EXCLUDED_GLOBS)
    for item in restricted_paths:
        clean = item.strip("/").strip()
        if clean:
            patterns.append(f"!{clean}/**")
    return patterns


def collect_rg_hits(repo_root: Path, search_roots: list[str], excluded_globs: list[str], pattern: str, limit: int, category: str | None = None) -> list[dict]:
    if not shutil.which("rg"):
        return []

    command = ["rg", "-n", "-i", "--no-heading", "--line-number", "--color", "never"]
    for glob in excluded_globs:
        command.extend(["-g", glob])
    command.extend([pattern, *search_roots])
    try:
        result = run_command(command, cwd=repo_root, check=False)
    except OSError:
        return []

    hits = []
    seen = set()
    for raw_line in result.stdout.splitlines():
        try:
            path_text, line_text, snippet = raw_line.split(":", 2)
            line_number = int(line_text)
        except ValueError:
            continue
        normalized_path = path_text[2:] if path_text.startswith("./") else path_text
        key = (normalized_path, line_number)
        if key in seen:
            continue
        seen.add(key)
        full_path = repo_root / normalized_path
        hits.append(
            {
                "path": normalized_path,
                "line": line_number,
                "snippet": snippet.strip(),
                "loc": file_loc(full_path),
                "category": category,
            }
        )
        if len(hits) >= limit:
            break
    return hits


def collect_code_evidence(repo_root: Path, search_roots: list[str], excluded_globs: list[str], keywords: list[str], limit: int) -> list[dict]:
    if not keywords:
        return []
    pattern = "|".join(re.escape(keyword) for keyword in keywords)
    hits = collect_rg_hits(repo_root, search_roots, excluded_globs, pattern, limit * 6)
    if not hits:
        return []

    keyword_counter = Counter(keywords)
    for hit in hits:
        haystack = f"{hit['path']} {hit['snippet']}".lower()
        hit["score"] = sum(keyword_counter[token] for token in keywords if token in haystack) + path_priority(hit["path"])
    if any(is_code_like_path(hit["path"]) for hit in hits):
        hits = [hit for hit in hits if is_code_like_path(hit["path"])]
    hits.sort(key=lambda item: (-item["score"], item["path"], item["line"]))
    return hits[:limit]


def collect_auth_signals(repo_root: Path, search_roots: list[str], excluded_globs: list[str], limit: int) -> list[dict]:
    results = []
    seen = set()
    per_category_limit = max(2, limit)
    for category, pattern in AUTH_PATTERNS:
        for hit in collect_rg_hits(repo_root, search_roots, excluded_globs, pattern, per_category_limit, category):
            key = (hit["path"], hit["line"])
            if key in seen:
                continue
            seen.add(key)
            results.append(hit)
            if len(results) >= limit:
                return results
    if any(is_code_like_path(hit["path"]) for hit in results):
        results = [hit for hit in results if is_code_like_path(hit["path"])]
    return results[:limit]


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


def fetch_linear_context(project_slug: str, limit: int) -> dict | None:
    if not os.environ.get("LINEAR_API_KEY", "").strip():
        return None
    try:
        data = graphql(PROJECT_CONTEXT_QUERY, {"projectId": project_slug, "first": limit})
    except RuntimeError as exc:
        if "labels" not in str(exc).lower():
            raise
        data = graphql(PROJECT_CONTEXT_QUERY_NO_LABELS, {"projectId": project_slug, "first": limit})
        project = data.get("project")
        if not project:
            return None
        teams = project.get("teams", {}).get("nodes", [])
        if not teams:
            raise RuntimeError(f"Linear project '{project_slug}' has no associated teams.")
        team = teams[0]
        if "labels" not in team:
            team["labels"] = {"nodes": []}
        project["team"] = team
        return project
    project = data.get("project")
    if not project:
        return None
    teams = project.get("teams", {}).get("nodes", [])
    if not teams:
        raise RuntimeError(f"Linear project '{project_slug}' has no associated teams.")
    project["team"] = teams[0]
    return project


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


def resolve_state_id(states: list[dict], requested_state: str) -> tuple[str, str]:
    lowered = requested_state.lower()
    for state in states:
        if (state.get("name") or "").lower() == lowered:
            return state["id"], state["name"]
    if lowered == "triage":
        for fallback in states:
            if (fallback.get("name") or "").lower() == "backlog":
                return fallback["id"], fallback["name"]
    raise SystemExit(f"Linear state '{requested_state}' was not found on the target team.")


def resolve_label_ids(labels: list[dict], requested_labels: list[str]) -> tuple[list[str], list[str]]:
    if not requested_labels:
        return [], []
    by_name = {(label.get("name") or "").lower(): label["id"] for label in labels}
    found = []
    missing = []
    for label_name in requested_labels:
        label_id = by_name.get(label_name.lower())
        if label_id:
            found.append(label_id)
        else:
            missing.append(label_name)
    return found, missing


def related_issue_score(issue_title: str, keywords: list[str]) -> float:
    if not keywords:
        return 0.0
    title_tokens = set(extract_keywords(issue_title, limit=16))
    keyword_set = set(keywords)
    overlap = len(keyword_set & title_tokens)
    if overlap == 0:
        return 0.0
    return overlap / max(len(keyword_set), 1)


def select_related_issues(issues: list[dict], keywords: list[str], limit: int, exclude_identifier: str | None) -> list[dict]:
    ranked = []
    for issue in issues:
        if exclude_identifier and issue.get("identifier") == exclude_identifier:
            continue
        score = related_issue_score(issue.get("title", ""), keywords)
        if score <= 0:
            continue
        ranked.append(
            {
                "identifier": issue["identifier"],
                "title": issue["title"],
                "url": issue.get("url"),
                "state": issue.get("state", {}).get("name"),
                "score": score,
            }
        )
    ranked.sort(key=lambda item: (-item["score"], item["identifier"]))
    return ranked[:limit]


def derive_title(project_name: str, task: str) -> str:
    for raw_line in task.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        line = re.sub(r"^[#>*\-\d\.\)\s]+", "", line)
        line = re.sub(r"\s+", " ", line).strip(" .:-")
        if not line:
            continue
        words = line.split()
        if len(line) > 96:
            line = " ".join(words[:12]).strip()
        return line[:120]
    return f"Investigate intake for {project_name}"


def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "intake"


def quote_block(text: str) -> str:
    return "\n".join(f"> {line}" if line else ">" for line in text.splitlines()) or "> "


def format_hit_lines(hits: list[dict], include_category: bool = False) -> list[str]:
    if not hits:
        return ["- No matching evidence was found automatically; verify scope manually before moving to `Todo`."]
    lines = []
    for hit in hits:
        prefix = f"[{hit['category']}] " if include_category and hit.get("category") else ""
        snippet = hit["snippet"][:180].strip()
        lines.append(f"- {prefix}`{hit['path']}:{hit['line']}` ({hit['loc']} LOC) {snippet}")
    return lines


def format_related_lines(issues: list[dict]) -> list[str]:
    if not issues:
        return ["- No obvious related issues were found from current title overlap."]
    return [f"- `{issue['identifier']}` [{issue['state']}] {issue['title']}" for issue in issues]


def unique_items(items: list[str]) -> list[str]:
    seen = set()
    result = []
    for item in items:
        normalized = item.strip()
        if not normalized:
            continue
        key = normalized.lower()
        if key in seen:
            continue
        seen.add(key)
        result.append(normalized)
    return result


def render_checkbox_items(items: list[str]) -> list[str]:
    cleaned = [item.strip() for item in items if item.strip()]
    if not cleaned:
        cleaned = ["Confirm the exact execution scope before moving this issue to `Todo`."]
    return [f"- [ ] {item}" for item in cleaned]


def render_bullet_items(items: list[str], empty_fallback: str = "None recorded yet.") -> list[str]:
    cleaned = [item.strip() for item in items if item.strip()]
    if not cleaned:
        cleaned = [empty_fallback]
    return [f"- {item}" for item in cleaned]


def indent_block(text: str, prefix: str = "  ") -> str:
    return "\n".join(f"{prefix}{line}" for line in text.splitlines())


def build_prompt(*, project: dict, task: str, title_seed: str, diagnosis: dict, evidence: list[dict], auth_signals: list[dict], related_issues: list[dict], existing_issue: dict | None) -> str:
    evidence_block = "\n".join(format_hit_lines(evidence)) or "- none"
    auth_block = "\n".join(format_hit_lines(auth_signals, include_category=True)) or "- none"
    related_block = "\n".join(format_related_lines(related_issues)) or "- none"
    existing_block = "No existing issue is being refined."
    if existing_issue:
        existing_block = "\n".join(
            [
                f"Existing issue under refinement: {existing_issue['identifier']}",
                f"- Title: {existing_issue['title']}",
                f"- State: {existing_issue['state']['name']}",
                f"- URL: {existing_issue['url']}",
                "- Current description:",
                indent_block(existing_issue.get("description") or "(empty)"),
            ]
        )

    diagnosis_lines = [
        f"- Fetched origin/{diagnosis['defaultBranch']}: {'yes' if diagnosis['fetched'] else 'no'}",
        *([f"- Fetch warning: {diagnosis['fetchError']}"] if diagnosis.get("fetchError") else []),
        f"- Current branch: {diagnosis.get('currentBranch') or 'detached HEAD'}",
        f"- Local {diagnosis['defaultBranch']} SHA: {diagnosis.get('localDefaultSha') or 'unavailable'}",
        f"- origin/{diagnosis['defaultBranch']} SHA: {diagnosis.get('remoteDefaultSha') or 'unavailable'}",
        f"- origin/{diagnosis['defaultBranch']} subject: {diagnosis.get('remoteDefaultSubject') or 'unavailable'}",
        f"- Ahead/behind: ahead={diagnosis.get('aheadOfRemote')}, behind={diagnosis.get('behindRemote')}",
        f"- Dirty state: tracked={diagnosis['trackedDirty']}, untracked={diagnosis['untrackedDirty']}",
        "- Recent origin/main commits:",
        indent_block("\n".join(f"- {line}" for line in diagnosis.get("recentRemoteCommits", [])) or "- unavailable"),
    ]

    return "\n".join(
        [
            "You are compiling a Symphony Hub issue intake request. You are not implementing code.",
            "",
            "Goal:",
            "- Turn the task into one narrow, reviewable Linear issue draft.",
            "- Ground it in the current repo and current mainline state.",
            "- Keep it safe and conservative: default recommendation should usually be Triage, not Todo.",
            "",
            f"Project: {project['name']}",
            f"Repo root: {project['repo_root']}",
            f"GitHub URL: {project['github_url']}",
            f"Default branch: {diagnosis['defaultBranch']}",
            f"Title seed: {title_seed}",
            "",
            "Raw task:",
            task,
            "",
            "Repo diagnosis:",
            *diagnosis_lines,
            "",
            "Code evidence:",
            evidence_block,
            "",
            "Authorization / restriction evidence:",
            auth_block,
            "",
            "Related Linear issues:",
            related_block,
            "",
            existing_block,
            "",
            "Output requirements:",
            "- Return JSON only and follow the provided schema exactly.",
            "- Fill every field with concise, concrete text.",
            "- Keep acceptance criteria and validation observable.",
            "- likely_code_locations should name repo-relative paths and explain why they matter.",
            "- authorizations and restrictions should be action-oriented.",
            "- If the task overlaps an existing issue, note that in related_issues and open_questions.",
            "- Do not suggest deleting history. Archive or supersede instead.",
            "- Treat canonical repo-root execution as restricted; implementation should happen in a fresh issue worktree from origin/main.",
            "- Do not inspect the filesystem or run tools. Use only the supplied diagnosis, evidence, and issue context.",
        ]
    )


def fallback_compile(task: str, title_seed: str, evidence: list[dict], related_issues: list[dict], existing_issue: dict | None) -> dict:
    likely_locations = []
    seen_paths = set()
    for hit in evidence:
        path = hit["path"]
        if path in seen_paths:
            continue
        seen_paths.add(path)
        likely_locations.append(
            {
                "path": path,
                "reason": f"Evidence matched at line {hit['line']} with {hit['loc']} LOC in the file.",
            }
        )
        if len(likely_locations) >= 5:
            break

    related = []
    for issue in related_issues[:3]:
        related.append(
            {
                "identifier": issue["identifier"],
                "reason": f"Title overlap with current task while in state {issue['state']}.",
            }
        )

    return {
        "title": (existing_issue or {}).get("title") or title_seed,
        "recommended_state": DEFAULT_CREATE_STATE,
        "labels": [],
        "operator_summary": "Deterministic fallback draft generated because Codex intake compilation did not complete in time.",
        "context": "This issue comes from a raw operator request and should be tightened against the evidence before execution.",
        "problem": "The request needs a stable spec with current code evidence, likely touched files, and explicit guardrails before it can become agent work.",
        "desired_outcome": "Produce one narrow issue that can be reviewed, clarified, and only then promoted to `Todo`.",
        "acceptance_criteria": [
            "The request is restated against current product behavior.",
            "The likely touched files are confirmed from the evidence section.",
            "Auth or restriction behavior is preserved or explicitly updated.",
            "Validation is concrete enough for a later agent or reviewer to execute.",
        ],
        "validation_steps": [
            "Review the current app or code path against the evidence before execution.",
            "Confirm the likely code locations are still current on `origin/main`.",
            "Add tests, screenshots, or commands before moving to `Todo`.",
        ],
        "assets": ["Review the local intake report bundle before promoting the issue."],
        "non_goals": [
            "Do not broaden the issue beyond the evidenced surface without creating a follow-up.",
            "Do not bypass review and move straight into implementation from this fallback draft.",
        ],
        "likely_code_locations": likely_locations,
        "authorizations": [
            "Inspect the current repo, related issues, and preserved runtime evidence.",
            "Use the intake bundle as the starting point for issue refinement.",
        ],
        "restrictions": [
            "Do not delete issue history or older attempts; archive or supersede instead.",
            "Do not execute from the canonical repo root.",
        ],
        "open_questions": (
            ["Does this overlap enough with an existing issue that it should refresh or supersede that issue instead of creating a new one?"]
            if related
            else ["Which exact user flow or screen should be treated as the primary validation target?"]
        ),
        "related_issues": related,
    }


def validate_compiled_payload(payload: dict) -> bool:
    required_text_fields = ["title", "recommended_state", "operator_summary", "context", "problem", "desired_outcome"]
    return all(str(payload.get(field, "")).strip() for field in required_text_fields)


def compile_with_codex(schema_path: Path, prompt: str, model: str | None) -> dict:
    if not shutil.which("codex"):
        raise SystemExit("codex CLI is required for diagnosis-backed intake.")
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
            result = subprocess.run(
                cmd,
                input=prompt,
                text=True,
                capture_output=True,
                check=False,
                timeout=DEFAULT_CODEX_TIMEOUT_SECONDS,
            )
            if result.returncode != 0:
                raise SystemExit(
                    "Codex intake compilation failed.\n"
                    f"stdout:\n{result.stdout}\n\nstderr:\n{result.stderr}"
                )
            raw = output_path.read_text(encoding="utf-8")
            return json.loads(raw)
        except subprocess.TimeoutExpired as exc:
            raise TimeoutError("Codex intake compilation timed out.") from exc
        finally:
            output_path.unlink(missing_ok=True)


def render_location_items(items: list[dict]) -> list[str]:
    if not items:
        return ["- No concrete code locations were identified. Keep this issue in `Triage` until the surface is clearer."]
    lines = []
    for item in items:
        path = (item.get("path") or "").strip()
        reason = (item.get("reason") or "").strip()
        if not path:
            continue
        lines.append(f"- `{path}`: {reason}" if reason else f"- `{path}`")
    return lines or ["- No concrete code locations were identified. Keep this issue in `Triage` until the surface is clearer."]


def build_managed_block(*, task: str, project: dict, diagnosis: dict, evidence: list[dict], auth_signals: list[dict], compiled: dict, related_issues: list[dict], report_dir: Path, existing_issue: dict | None, requested_state: str) -> str:
    compiled_related = compiled.get("related_issues") or []
    related_lines = [f"- `{item['identifier']}`: {item['reason']}" for item in compiled_related] or format_related_lines(related_issues)
    authorizations = unique_items(
        [
            "Inspect the configured repo, current mainline, related issues, and preserved runtime evidence before execution.",
            "Implement in a fresh issue worktree branched from `origin/main`.",
            *compiled.get("authorizations", []),
        ]
    )
    restrictions = unique_items(
        [
            "Do not delete workflow history; archive or supersede stale paths instead.",
            "Do not execute from the canonical repo root; use a per-issue worktree.",
            "Do not move this issue to `Todo` until the operator confirms the spec is current.",
            *([] if not diagnosis["dirty"] else ["The configured repo root is currently dirty; preserve that state and avoid using it as the execution workspace."]),
            *(["Refresh from current `origin/main` before implementation because the local default branch is behind."] if diagnosis.get("behindRemote") not in (None, 0) else []),
            *compiled.get("restrictions", []),
        ]
    )

    sections = [
        MANAGED_BLOCK_START,
        "## Source Task",
        quote_block(task),
        "",
        "## Intake Diagnosis",
        *render_bullet_items(
            [
                f"Project: `{project['name']}`",
                f"Repo root: `{project['repo_root']}`",
                f"Requested create state: `{requested_state}`",
                f"Intake report bundle: `{report_dir}`",
                f"Captured at: `{diagnosis['timestampUtc']}`",
                f"Current branch: `{diagnosis.get('currentBranch') or 'detached HEAD'}`",
                f"Local `{diagnosis['defaultBranch']}`: `{diagnosis.get('localDefaultSha') or 'unavailable'}`",
                f"`origin/{diagnosis['defaultBranch']}`: `{diagnosis.get('remoteDefaultSha') or 'unavailable'}`",
                f"Remote subject: {diagnosis.get('remoteDefaultSubject') or 'unavailable'}",
                f"Ahead/behind vs `origin/{diagnosis['defaultBranch']}`: `{diagnosis.get('aheadOfRemote')}` ahead / `{diagnosis.get('behindRemote')}` behind",
                f"Working tree: `{diagnosis['trackedDirty']}` tracked dirty, `{diagnosis['untrackedDirty']}` untracked",
                *(["Existing issue under refinement: `{}`".format(existing_issue["identifier"])] if existing_issue else []),
            ]
        ),
        "",
        "## Code Evidence",
        *format_hit_lines(evidence),
        "",
        "## Authorization / Restriction Evidence",
        *format_hit_lines(auth_signals, include_category=True),
        "",
        "## Likely Code Locations (LOC)",
        *render_location_items(compiled.get("likely_code_locations", [])),
        "",
        "## Related Linear Context",
        *related_lines,
        "",
        "## Execution Guardrails",
        "### Authorizations",
        *render_bullet_items(authorizations),
        "",
        "### Restrictions",
        *render_bullet_items(restrictions),
        MANAGED_BLOCK_END,
    ]
    return "\n".join(sections).rstrip() + "\n"


def render_spec_sections(*, task: str, compiled: dict, report_dir: Path) -> str:
    return render_signature_sections(
        {
            "context": compiled["context"].strip(),
            "problem": compiled["problem"].strip(),
            "desired_outcome": compiled["desired_outcome"].strip(),
            "acceptance_criteria": compiled.get("acceptance_criteria", []),
            "validation": compiled.get("validation_steps", []),
            "assets": unique_items(
                [
                    f"Original task: {task}",
                    f"Intake report bundle: `{report_dir}`",
                    *compiled.get("assets", []),
                ]
            ),
            "non_goals": compiled.get("non_goals", []),
            "open_questions": compiled.get("open_questions", []),
        },
        SIGNATURE,
    )


def render_description(*, task: str, project: dict, diagnosis: dict, evidence: list[dict], auth_signals: list[dict], compiled: dict, related_issues: list[dict], report_dir: Path, existing_issue: dict | None, requested_state: str) -> str:
    managed_block = build_managed_block(
        task=task,
        project=project,
        diagnosis=diagnosis,
        evidence=evidence,
        auth_signals=auth_signals,
        compiled=compiled,
        related_issues=related_issues,
        report_dir=report_dir,
        existing_issue=existing_issue,
        requested_state=requested_state,
    )
    spec_sections = render_spec_sections(task=task, compiled=compiled, report_dir=report_dir)
    return "\n".join([managed_block.rstrip(), "", spec_sections.rstrip()]).rstrip() + "\n"


def upsert_managed_block(existing_description: str, managed_block: str) -> str:
    return signature_upsert_managed_block(existing_description, managed_block, SIGNATURE)


def write_report_bundle(report_root: Path, slug: str, payload: dict, draft: str, task: str, compiled: dict) -> Path:
    report_root.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    report_dir = report_root / f"{timestamp}-{slug}"
    report_dir.mkdir(parents=True, exist_ok=False)
    (report_dir / "request.txt").write_text(task.strip() + "\n", encoding="utf-8")
    (report_dir / "diagnosis.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    (report_dir / "compiled.json").write_text(json.dumps(compiled, indent=2) + "\n", encoding="utf-8")
    (report_dir / "draft.md").write_text(draft, encoding="utf-8")
    return report_dir


def render_intake_comment(mode: str, diagnostics: dict, compiled: dict, task: str, state_name: str) -> str:
    return "\n".join(
        [
            "## Intake Compilation",
            "",
            f"- Mode: `{mode}`",
            f"- Compiled at: `{datetime.now(timezone.utc).strftime('%Y-%m-%d %H:%M:%SZ')}`",
            f"- Recommended state: `{compiled['recommended_state']}`",
            f"- Applied state: `{state_name}`",
            f"- Suggested labels: {', '.join(compiled.get('labels', [])) or 'none'}",
            f"- Remote main reference: `{diagnostics.get('remoteDefaultSha') or 'unavailable'}`",
            f"- Repo state during intake: `{diagnostics['trackedDirty']}` tracked dirty / `{diagnostics['untrackedDirty']}` untracked",
            f"- Operator summary: {compiled['operator_summary']}",
            f"- Source task: {task}",
            "- Preserve history. Refine, supersede, or archive; do not delete.",
        ]
    )


def create_comment(issue_id: str, body: str) -> None:
    data = graphql(COMMENT_CREATE_MUTATION, {"issueId": issue_id, "body": body})
    if (data.get("commentCreate") or {}).get("success") is not True:
        raise RuntimeError("commentCreate returned success=false")


def create_issue(project_context: dict, title: str, description: str, requested_state: str, requested_labels: list[str]) -> tuple[dict, list[str], str]:
    team = project_context["team"]
    states = team.get("states", {}).get("nodes", [])
    labels = team.get("labels", {}).get("nodes", [])
    state_id, resolved_state = resolve_state_id(states, requested_state)
    label_ids, missing_labels = resolve_label_ids(labels, requested_labels)
    issue_input = {
        "teamId": team["id"],
        "projectId": project_context["id"],
        "stateId": state_id,
        "title": title,
        "description": description,
    }
    if label_ids:
        issue_input["labelIds"] = label_ids
    data = graphql(CREATE_ISSUE_MUTATION, {"input": issue_input})
    created = data.get("issueCreate", {})
    if created.get("success") is not True:
        raise RuntimeError("issueCreate returned success=false")
    return created["issue"], missing_labels, resolved_state


def update_issue(issue: dict, title: str | None, description: str, requested_labels: list[str], project_context: dict | None, requested_state: str | None, apply_state: bool) -> tuple[dict, list[str], str]:
    input_payload = {"description": description}
    if title is not None:
        input_payload["title"] = title
    missing_labels = []
    resolved_state = issue["state"]["name"]
    if project_context and requested_labels:
        label_ids, missing_labels = resolve_label_ids(project_context["team"].get("labels", {}).get("nodes", []), requested_labels)
        input_payload["labelIds"] = label_ids
    if project_context and apply_state and requested_state:
        state_id, resolved_state = resolve_state_id(project_context["team"]["states"]["nodes"], requested_state)
        input_payload["stateId"] = state_id
    data = graphql(UPDATE_ISSUE_MUTATION, {"id": issue["id"], "input": input_payload})
    updated = data.get("issueUpdate", {})
    if updated.get("success") is not True:
        raise RuntimeError("issueUpdate returned success=false")
    return updated["issue"], missing_labels, resolved_state


def default_labels(compiled: dict, explicit_labels: str, existing_issue: dict | None) -> list[str]:
    if explicit_labels.strip():
        return [item.strip() for item in explicit_labels.split(",") if item.strip()]
    if existing_issue:
        return []
    return [item.strip() for item in compiled.get("labels", []) if item.strip()]


def preview(project: dict, title: str, report_dir: Path, compiled: dict, draft: str, issue_identifier: str | None, apply: bool, compile_mode: str) -> None:
    print("Linear intake draft")
    print(f"  Project: {project['name']}")
    print(f"  Mode: {'apply' if apply else 'dry-run'}")
    print(f"  Compile mode: {compile_mode}")
    print(f"  Title: {title}")
    print(f"  Recommended state: {compiled['recommended_state']}")
    print(f"  Report bundle: {report_dir}")
    print(f"  Suggested labels: {', '.join(compiled.get('labels', [])) or 'none'}")
    if issue_identifier:
        print(f"  Existing issue: {issue_identifier}")
    print(f"  Summary: {compiled['operator_summary']}")
    print()
    print(draft, end="")


def main() -> int:
    args = parse_args()
    task = load_task(args)
    config = load_config(Path(os.environ["CONFIG_FILE"]))
    project = get_project(config, args.project)
    intake_config = project.get("intake", {})
    default_branch = project.get("default_branch") or config.get("defaults", {}).get("default_branch", "main")
    repo_root = Path(project["repo_root"]).expanduser()
    if not repo_root.exists():
        raise SystemExit(f"Configured repo_root does not exist: {repo_root}")

    search_roots = normalize_roots(repo_root, intake_config.get("writable_paths", []))
    excluded_globs = build_excluded_globs(intake_config.get("restricted_paths", []))
    linear_context = fetch_linear_context(project["linear_project_slug"], max(args.context_issues, 25))
    existing_issue = fetch_issue(args.issue) if args.issue else None
    if existing_issue and linear_context and existing_issue.get("project", {}).get("id") != linear_context["id"]:
        raise SystemExit(f"{args.issue} does not belong to configured project '{args.project}'.")

    title_seed = (args.title or (existing_issue or {}).get("title") or derive_title(project["name"], task)).strip()
    keyword_source = "\n".join(
        item
        for item in [
            title_seed,
            task,
            (existing_issue or {}).get("title", ""),
        ]
        if item
    )
    keywords = extract_keywords(keyword_source)
    diagnosis = collect_git_diagnosis(repo_root, default_branch, fetch=not args.no_fetch)
    evidence = collect_code_evidence(repo_root, search_roots, excluded_globs, keywords, args.evidence_limit)
    auth_signals = collect_auth_signals(repo_root, search_roots, excluded_globs, args.auth_limit)
    related = select_related_issues(
        linear_context.get("issues", {}).get("nodes", []) if linear_context else [],
        keywords,
        args.related_limit,
        args.issue,
    )

    compile_mode = "codex"
    if args.skip_compile:
        compiled = fallback_compile(task, title_seed, evidence, related, existing_issue)
        compile_mode = "skipped"
    else:
        try:
            compiled = compile_with_codex(
                schema_path=Path(os.environ["SCRIPT_DIR"]) / "schemas" / "linear-intake-output.schema.json",
                prompt=build_prompt(
                    project=project,
                    task=task,
                    title_seed=title_seed,
                    diagnosis=diagnosis,
                    evidence=evidence,
                    auth_signals=auth_signals,
                    related_issues=related,
                    existing_issue=existing_issue,
                ),
                model=args.model,
            )
            if not validate_compiled_payload(compiled):
                raise ValueError("Codex returned an incomplete intake payload.")
        except (TimeoutError, ValueError):
            compiled = fallback_compile(task, title_seed, evidence, related, existing_issue)
            compile_mode = "fallback"

    resolved_title = (args.title or (existing_issue or {}).get("title") or compiled.get("title") or title_seed).strip()
    report_payload = {
        "project": {
            "name": project["name"],
            "repoRoot": str(repo_root),
            "defaultBranch": default_branch,
            "linearProjectSlug": project["linear_project_slug"],
        },
        "intakeConfig": intake_config,
        "titleSeed": title_seed,
        "resolvedTitle": resolved_title,
        "keywords": keywords,
        "gitDiagnosis": diagnosis,
        "codeEvidence": evidence,
        "authSignals": auth_signals,
        "relatedIssues": related,
        "recommendedState": compiled.get("recommended_state"),
        "compileMode": compile_mode,
    }

    report_root = Path(args.report_root).expanduser()
    report_slug = slugify(f"{project['name']}-{resolved_title}")[:80]
    placeholder_dir = report_root / "pending"
    placeholder_full_draft = render_description(
        task=task,
        project=project,
        diagnosis=diagnosis,
        evidence=evidence,
        auth_signals=auth_signals,
        compiled=compiled,
        related_issues=related,
        report_dir=placeholder_dir,
        existing_issue=existing_issue,
        requested_state=args.status,
    )
    report_dir = write_report_bundle(report_root, report_slug, report_payload, placeholder_full_draft, task, compiled)
    full_draft = render_description(
        task=task,
        project=project,
        diagnosis=diagnosis,
        evidence=evidence,
        auth_signals=auth_signals,
        compiled=compiled,
        related_issues=related,
        report_dir=report_dir,
        existing_issue=existing_issue,
        requested_state=args.status,
    )
    managed_block = build_managed_block(
        task=task,
        project=project,
        diagnosis=diagnosis,
        evidence=evidence,
        auth_signals=auth_signals,
        compiled=compiled,
        related_issues=related,
        report_dir=report_dir,
        existing_issue=existing_issue,
        requested_state=args.status,
    )
    if existing_issue and (existing_issue.get("description") or "").strip():
        draft = upsert_managed_block(existing_issue.get("description") or "", managed_block)
    else:
        draft = full_draft
    (report_dir / "draft.md").write_text(draft, encoding="utf-8")

    created_issue = None
    missing_labels = []
    applied_state = existing_issue["state"]["name"] if existing_issue else args.status
    requested_labels = default_labels(compiled, args.labels, existing_issue)

    if args.apply:
        if not linear_context:
            raise SystemExit("LINEAR_API_KEY is required for --apply.")
        if existing_issue:
            target_state = args.status if args.apply_state else existing_issue["state"]["name"]
            created_issue, missing_labels, applied_state = update_issue(
                issue=existing_issue,
                title=args.title.strip() if args.title else None,
                description=draft,
                requested_labels=requested_labels,
                project_context=linear_context,
                requested_state=target_state,
                apply_state=args.apply_state,
            )
            create_comment(created_issue["id"], render_intake_comment("update", diagnosis, compiled, task, applied_state))
        else:
            created_issue, missing_labels, applied_state = create_issue(
                project_context=linear_context,
                title=resolved_title,
                description=draft,
                requested_state=args.status,
                requested_labels=requested_labels,
            )
            create_comment(created_issue["id"], render_intake_comment("create", diagnosis, compiled, task, applied_state))
        (report_dir / "linear-response.json").write_text(
            json.dumps({"issue": created_issue, "missingLabels": missing_labels, "appliedState": applied_state}, indent=2) + "\n",
            encoding="utf-8",
        )

    output = {
        "project": project["name"],
        "title": resolved_title,
        "reportDir": str(report_dir),
        "task": task,
        "createdIssue": created_issue,
        "missingLabels": missing_labels,
        "appliedState": applied_state,
        "recommendedState": compiled.get("recommended_state"),
        "compileMode": compile_mode,
        "draft": draft,
        "compiled": compiled,
        "diagnosis": report_payload,
    }

    if args.json:
        print(json.dumps(output, indent=2))
        return 0

    preview(project, resolved_title, report_dir, compiled, draft, args.issue, args.apply, compile_mode)
    if args.apply and created_issue:
        print()
        print(f"Created/updated issue: {created_issue['identifier']} ({created_issue['url']})")
        print(f"Applied state: {applied_state}")
        if missing_labels:
            print(f"Missing labels ignored: {', '.join(missing_labels)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYTHON_SCRIPT
