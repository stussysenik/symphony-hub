#!/usr/bin/env bash
# linear-intake.sh - Turn a raw prompt into a diagnosis-backed Linear intake draft.

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

export LINEAR_API_KEY CONFIG_FILE SCRIPT_DIR
python3 - "$@" <<'PYTHON_SCRIPT'
import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.request
from collections import Counter
from datetime import datetime, timezone
from pathlib import Path

import yaml

LINEAR_API_URL = "https://api.linear.app/graphql"
DEFAULT_REPORT_ROOT = Path(os.environ["SCRIPT_DIR"]) / "intakes"
MANAGED_BLOCK_START = "<!-- symphony:intake:start -->"
MANAGED_BLOCK_END = "<!-- symphony:intake:end -->"
STOPWORDS = {
    "about", "after", "again", "against", "agent", "agents", "also", "always",
    "and", "another", "around", "because", "before", "being", "board", "both",
    "bring", "build", "built", "can", "clean", "could", "desktop", "does", "done",
    "each", "easy", "ensure", "everything", "feel", "from", "going", "have", "here",
    "into", "issue", "issues", "just", "keep", "like", "main", "make", "mobile",
    "must", "need", "next", "only", "onto", "over", "project", "really", "read",
    "repo", "right", "should", "start", "state", "still", "such", "sure", "that",
    "the", "them", "there", "these", "they", "thing", "this", "those", "through",
    "todo", "want", "were", "what", "when", "with", "work", "would", "write", "your",
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
    (
        "authorization",
        r"\b(auth|authorize|authorization|permission|permissions|rbac|acl|role|roles|policy|policies|guard)\b",
    ),
    (
        "identity-session",
        r"\b(session|jwt|token|oauth|clerk|nextauth|auth0|supabase)\b",
    ),
    (
        "restriction",
        r"\b(protected|readonly|read-only|forbidden|deny|scope|scopes|admin)\b",
    ),
]
PROJECT_CONTEXT_QUERY = """
query($projectId: String!, $first: Int!) {
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
ISSUE_LOOKUP_QUERY = """
query($teamKey: String!, $issueNumber: Float!) {
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
      team {
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
  }
}
"""
CREATE_ISSUE_MUTATION = """
mutation($input: IssueCreateInput!) {
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
mutation($id: String!, $input: IssueUpdateInput!) {
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


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="./linear-intake.sh",
        description="Draft a diagnosis-backed Linear intake issue from a raw prompt."
    )
    parser.add_argument("--project", required=True, help="Configured project name from projects.yml.")
    parser.add_argument("--title", help="Optional override for the generated or refreshed issue title.")
    parser.add_argument("--prompt", help="Raw prompt text.")
    parser.add_argument("--prompt-file", help="Path to a file containing the raw prompt.")
    parser.add_argument("--issue", help="Existing Linear issue identifier to refresh instead of creating a new one.")
    parser.add_argument("--status", help="Target Linear state when creating or updating an issue. Defaults to the project intake policy.")
    parser.add_argument("--labels", default="", help="Comma-separated label names to apply when creating a new issue.")
    parser.add_argument("--related-limit", type=int, default=5, help="Maximum related Linear issues to include.")
    parser.add_argument("--evidence-limit", type=int, default=8, help="Maximum code evidence hits to include.")
    parser.add_argument("--auth-limit", type=int, default=6, help="Maximum auth/restriction hits to include.")
    parser.add_argument("--report-root", default=str(DEFAULT_REPORT_ROOT), help="Local report directory root.")
    parser.add_argument("--no-fetch", action="store_true", help="Skip `git fetch origin <default-branch>` during diagnosis.")
    parser.add_argument("--sync-main", action="store_true", help="Fast-forward the local default branch when it is safe to do so.")
    parser.add_argument("--apply", action="store_true", help="Create or update the issue in Linear.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    return parser.parse_args()


def load_prompt(args: argparse.Namespace) -> str:
    if args.prompt:
        return args.prompt.strip()
    if args.prompt_file:
        return Path(args.prompt_file).read_text(encoding="utf-8").strip()
    if not sys.stdin.isatty():
        return sys.stdin.read().strip()
    return ""


def load_config(config_path: Path) -> dict:
    with config_path.open(encoding="utf-8") as handle:
        return yaml.safe_load(handle) or {}


def get_project(config: dict, project_name: str) -> dict:
    for project in config.get("projects", []):
        if project.get("name") == project_name:
            return project
    raise SystemExit(f"Configured project '{project_name}' not found in {os.environ['CONFIG_FILE']}")


def run_command(args: list[str], cwd: Path | None = None, check: bool = True) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        args,
        cwd=str(cwd) if cwd else None,
        check=check,
        text=True,
        capture_output=True,
    )


def safe_git_output(repo_root: Path, *args: str) -> str:
    try:
        result = run_command(["git", *args], cwd=repo_root, check=True)
    except subprocess.CalledProcessError:
        return ""
    return result.stdout.strip()


def git_ref_exists(repo_root: Path, ref: str) -> bool:
    return run_command(["git", "show-ref", "--verify", "--quiet", ref], cwd=repo_root, check=False).returncode == 0


def collect_git_diagnosis(repo_root: Path, default_branch: str, should_fetch: bool, should_sync: bool) -> dict:
    fetch = {"ran": False, "ok": False, "message": ""}
    if should_fetch:
        fetch_result = run_command(["git", "fetch", "--quiet", "origin", default_branch], cwd=repo_root, check=False)
        fetch = {
            "ran": True,
            "ok": fetch_result.returncode == 0,
            "message": fetch_result.stderr.strip() or fetch_result.stdout.strip(),
        }

    status_lines = safe_git_output(repo_root, "status", "--porcelain").splitlines()
    tracked_dirty = sum(1 for line in status_lines if line and not line.startswith("??"))
    untracked_dirty = sum(1 for line in status_lines if line.startswith("??"))
    current_branch = safe_git_output(repo_root, "branch", "--show-current")
    local_default_sha = safe_git_output(repo_root, "rev-parse", default_branch)
    remote_default_sha = safe_git_output(repo_root, "rev-parse", f"origin/{default_branch}")
    current_head = safe_git_output(repo_root, "rev-parse", "HEAD")
    current_subject = safe_git_output(repo_root, "log", "-1", "--format=%s", "HEAD")
    ahead = behind = None
    if local_default_sha and remote_default_sha:
        counts = safe_git_output(repo_root, "rev-list", "--left-right", "--count", f"{default_branch}...origin/{default_branch}")
        if counts:
            left, right = counts.split()
            ahead, behind = int(left), int(right)

    sync_result = "not-requested"
    if should_sync:
        if current_branch != default_branch:
            sync_result = f"skipped: current branch is `{current_branch or 'detached HEAD'}`, not `{default_branch}`"
        elif tracked_dirty or untracked_dirty:
            sync_result = f"skipped: working tree is dirty ({tracked_dirty} tracked, {untracked_dirty} untracked)"
        elif not git_ref_exists(repo_root, f"refs/heads/{default_branch}"):
            sync_result = f"skipped: local `{default_branch}` branch does not exist"
        else:
            pull_result = run_command(["git", "pull", "--ff-only", "origin", default_branch], cwd=repo_root, check=False)
            if pull_result.returncode == 0:
                sync_result = pull_result.stdout.strip() or pull_result.stderr.strip() or "ok: fast-forwarded"
                local_default_sha = safe_git_output(repo_root, "rev-parse", default_branch)
                counts = safe_git_output(repo_root, "rev-list", "--left-right", "--count", f"{default_branch}...origin/{default_branch}")
                if counts:
                    left, right = counts.split()
                    ahead, behind = int(left), int(right)
            else:
                sync_result = f"failed: {pull_result.stderr.strip() or pull_result.stdout.strip() or 'git pull failed'}"

    recent_default_commits = safe_git_output(repo_root, "log", "--oneline", "-n", "3", f"origin/{default_branch}")
    return {
        "fetched": fetch["ok"],
        "fetchRan": fetch["ran"],
        "fetchMessage": fetch["message"],
        "defaultBranch": default_branch,
        "currentBranch": current_branch or None,
        "currentHead": current_head or None,
        "currentSubject": current_subject or None,
        "localDefaultSha": local_default_sha or None,
        "remoteDefaultSha": remote_default_sha or None,
        "aheadOfRemote": ahead,
        "behindRemote": behind,
        "trackedDirty": tracked_dirty,
        "untrackedDirty": untracked_dirty,
        "dirty": bool(tracked_dirty or untracked_dirty),
        "syncResult": sync_result,
        "recentDefaultCommits": [line.strip() for line in recent_default_commits.splitlines() if line.strip()],
        "timestampUtc": datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M:%SZ"),
    }


def extract_keywords(text: str, limit: int = 10) -> list[str]:
    candidates = re.findall(r"[A-Za-z][A-Za-z0-9_-]{2,}", text.lower())
    ordered: list[str] = []
    seen: set[str] = set()
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


def is_noise_path(path_text: str) -> bool:
    lower = path_text.lower()
    return (
        lower == "package-lock.json"
        or lower == "yarn.lock"
        or lower == "pnpm-lock.yaml"
        or lower.endswith(".md")
        or lower.endswith(".mdx")
        or lower.endswith(".png")
        or lower.endswith(".jpg")
        or lower.endswith(".jpeg")
        or lower.endswith(".gif")
        or lower.endswith(".svg")
        or lower.startswith("docs/")
        or lower.startswith("openspec/")
        or lower.startswith("pr-screenshots/")
        or lower.startswith(".github/")
    )


def path_priority(path_text: str, writable_paths: list[str]) -> int:
    lower = path_text.lower()
    score = 0
    if any(segment in lower for segment in ("/app/", "/src/", "/components/", "/lib/", "/hooks/", "/pages/", "/ui/")):
        score += 3
    if any(segment in lower for segment in ("middleware", "auth", "session", "search", "header", "toolbar", "popup")):
        score += 2
    if lower.endswith((".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".css", ".scss")):
        score += 2
    if any(lower == root.lower() or lower.startswith(f"{root.lower()}/") for root in writable_paths):
        score += 2
    if is_noise_path(path_text):
        score -= 5
    return score


def collect_rg_hits(
    repo_root: Path,
    search_roots: list[str],
    excluded_globs: list[str],
    pattern: str,
    limit: int,
    category: str | None = None,
) -> list[dict]:
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

    hits: list[dict] = []
    seen: set[tuple[str, int]] = set()
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
        hits.append(
            {
                "path": normalized_path,
                "line": line_number,
                "snippet": snippet.strip(),
                "loc": file_loc(repo_root / normalized_path),
                "category": category,
            }
        )
        if len(hits) >= limit:
            break
    return hits


def collect_filename_hits(
    repo_root: Path,
    search_roots: list[str],
    excluded_globs: list[str],
    keywords: list[str],
    limit: int,
    category: str | None = None,
) -> list[dict]:
    if not shutil.which("rg") or not keywords:
        return []

    command = ["rg", "--files", *search_roots]
    for glob in excluded_globs:
        command.extend(["-g", glob])

    try:
        result = run_command(command, cwd=repo_root, check=False)
    except OSError:
        return []

    pattern = re.compile("|".join(re.escape(keyword) for keyword in keywords), re.IGNORECASE)
    hits: list[dict] = []
    for raw_path in result.stdout.splitlines():
        normalized_path = raw_path[2:] if raw_path.startswith("./") else raw_path
        if is_noise_path(normalized_path):
            continue
        if category == "authorization" and "author" in normalized_path.lower():
            continue
        if not pattern.search(normalized_path):
            continue
        hits.append(
            {
                "path": normalized_path,
                "line": 1,
                "snippet": "filename match",
                "loc": file_loc(repo_root / normalized_path),
                "category": category,
            }
        )
        if len(hits) >= limit:
            break
    return hits


def collect_code_evidence(
    repo_root: Path,
    search_roots: list[str],
    excluded_globs: list[str],
    writable_paths: list[str],
    keywords: list[str],
    limit: int,
) -> list[dict]:
    if not keywords:
        return []

    pattern = "|".join(re.escape(keyword) for keyword in keywords)
    hits = [
        hit
        for hit in collect_rg_hits(repo_root, search_roots, excluded_globs, pattern, limit * 8)
        if not is_noise_path(hit["path"])
    ]
    hits.extend(collect_filename_hits(repo_root, search_roots, excluded_globs, keywords, limit * 4))
    if not hits:
        return []

    keyword_counter = Counter(keywords)
    deduped: dict[tuple[str, int], dict] = {}
    for hit in hits:
        haystack = f"{hit['path']} {hit['snippet']}".lower()
        hit["score"] = sum(keyword_counter[token] for token in keywords if token in haystack) + path_priority(hit["path"], writable_paths)
        key = (hit["path"], hit["line"])
        previous = deduped.get(key)
        if previous is None or hit["score"] > previous["score"]:
            deduped[key] = hit

    ranked = list(deduped.values())
    ranked.sort(key=lambda item: (-item["score"], item["path"], item["line"]))
    return ranked[:limit]


def collect_auth_signals(repo_root: Path, search_roots: list[str], excluded_globs: list[str], limit: int) -> list[dict]:
    results: list[dict] = []
    seen: set[tuple[str, int]] = set()
    per_category_limit = max(2, limit)

    for category, pattern in AUTH_PATTERNS:
        search_terms = [term for term in re.findall(r"[A-Za-z]+", pattern) if len(term) > 3]
        filename_hits = collect_filename_hits(repo_root, search_roots, excluded_globs, search_terms, per_category_limit, category)
        content_hits = collect_rg_hits(repo_root, search_roots, excluded_globs, pattern, per_category_limit, category)
        for hit in filename_hits + content_hits:
            if is_noise_path(hit["path"]):
                continue
            key = (hit["path"], hit["line"])
            if key in seen:
                continue
            seen.add(key)
            results.append(hit)
            if len(results) >= limit:
                return results
    return results[:limit]


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


def fetch_linear_context(project_slug: str, team_key: str | None) -> dict:
    data = graphql(PROJECT_CONTEXT_QUERY, {"projectId": project_slug, "first": 100})
    project = data.get("project")
    if project is None:
        raise SystemExit(f"Linear project '{project_slug}' was not found.")
    teams = project.get("teams", {}).get("nodes", [])
    if not teams:
        raise SystemExit(f"Linear project '{project_slug}' has no associated teams.")
    if team_key:
        for team in teams:
            if team.get("key") == team_key:
                project["team"] = team
                return project
        raise SystemExit(f"Configured team '{team_key}' was not found on project '{project_slug}'.")
    project["team"] = teams[0]
    return project


def fetch_issue(issue_identifier: str) -> dict:
    team_key, number = issue_identifier.rsplit("-", 1)
    data = graphql(ISSUE_LOOKUP_QUERY, {"teamKey": team_key, "issueNumber": int(number)})
    nodes = data.get("issues", {}).get("nodes", [])
    if not nodes:
        raise SystemExit(f"Linear issue '{issue_identifier}' was not found.")
    return nodes[0]


def resolve_state_id(states: list[dict], requested_state: str) -> tuple[str, str]:
    lowered = requested_state.lower()
    for state in states:
        if (state.get("name") or "").lower() == lowered:
            return state["id"], state["name"]
    if lowered == "triage":
        for state in states:
            if (state.get("name") or "").lower() == "backlog":
                return state["id"], state["name"]
    raise SystemExit(f"Linear state '{requested_state}' was not found on the target team.")


def resolve_label_ids(labels: list[dict], requested_labels: list[str]) -> tuple[list[str], list[str]]:
    if not requested_labels:
        return [], []
    by_name = {(label.get("name") or "").lower(): label["id"] for label in labels}
    found: list[str] = []
    missing: list[str] = []
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
    if overlap < 2 and len(keyword_set) >= 5:
        return 0.0
    return overlap / max(len(keyword_set), 1)


def select_related_issues(issues: list[dict], keywords: list[str], limit: int, exclude_identifier: str | None = None) -> list[dict]:
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
                "url": issue["url"],
                "state": issue.get("state", {}).get("name"),
                "score": score,
            }
        )
    ranked.sort(key=lambda item: (-item["score"], item["identifier"]))
    return ranked[:limit]


def derive_title(project_name: str, prompt: str) -> str:
    for raw_line in prompt.splitlines():
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
    if not text.strip():
        return "> _No new prompt provided; diagnosis refreshed against current repo state._"
    return "\n".join(f"> {line}" if line else ">" for line in text.splitlines())


def summarize_git_diagnosis(diagnosis: dict) -> list[str]:
    lines = []
    if diagnosis.get("fetchRan"):
        lines.append(f"- Fetched `origin/{diagnosis['defaultBranch']}` for diagnosis at {diagnosis['timestampUtc']}.")
    else:
        lines.append(f"- Skipped fetch; diagnosis used local refs at {diagnosis['timestampUtc']}.")
    if diagnosis.get("fetchMessage"):
        lines.append(f"- Fetch note: `{diagnosis['fetchMessage']}`")
    current_branch = diagnosis.get("currentBranch") or "detached HEAD"
    lines.append(f"- Current branch: `{current_branch}`.")
    if diagnosis.get("localDefaultSha") and diagnosis.get("remoteDefaultSha"):
        lines.append(
            f"- Local `{diagnosis['defaultBranch']}` is `{diagnosis['behindRemote']}` behind / `{diagnosis['aheadOfRemote']}` ahead of `origin/{diagnosis['defaultBranch']}`."
        )
    else:
        lines.append(f"- Local `{diagnosis['defaultBranch']}` ref is unavailable; verify the checkout before execution.")
    if diagnosis.get("dirty"):
        lines.append(f"- Working tree has `{diagnosis['trackedDirty']}` tracked and `{diagnosis['untrackedDirty']}` untracked local changes.")
    else:
        lines.append("- Working tree is clean.")
    if diagnosis.get("syncResult") != "not-requested":
        lines.append(f"- Sync result: {diagnosis['syncResult']}")
    if diagnosis.get("recentDefaultCommits"):
        lines.append(f"- Recent `origin/{diagnosis['defaultBranch']}` commits:")
        for commit in diagnosis["recentDefaultCommits"]:
            lines.append(f"  - `{commit}`")
    return lines


def format_hit_lines(hits: list[dict], include_category: bool = False) -> list[str]:
    if not hits:
        return ["- No matching evidence was found automatically; verify scope manually before moving to `Todo`."]
    lines: list[str] = []
    for hit in hits:
        prefix = f"[{hit['category']}] " if include_category and hit.get("category") else ""
        lines.append(f"- {prefix}`{hit['path']}:{hit['line']}` ({hit['loc']} LOC) {hit['snippet'][:180].strip()}")
    return lines


def format_related_issues(issues: list[dict]) -> list[str]:
    if not issues:
        return ["- No obvious related issues were found from current title overlap."]
    return [f"- `{issue['identifier']}` [{issue['state']}] {issue['title']}" for issue in issues]


def build_execution_boundaries(intake_config: dict) -> list[str]:
    writable = intake_config.get("writable_paths", [])
    restricted = intake_config.get("restricted_paths", [])
    checks = intake_config.get("required_checks", [])
    notes = intake_config.get("notes", [])

    lines = ["### Writable Paths"]
    lines.extend([f"- `{item}`" for item in writable] or ["- No project-specific writable paths were configured."])
    lines.append("")
    lines.append("### Restricted Paths")
    lines.extend([f"- `{item}`" for item in restricted] or ["- No additional restricted paths were configured."])
    lines.append("")
    lines.append("### Required Checks")
    lines.extend([f"- `{item}`" for item in checks] or ["- No required checks were configured."])
    if notes:
        lines.append("")
        lines.append("### Intake Notes")
        lines.extend([f"- {item}" for item in notes])
    return lines


def build_managed_block(
    *,
    project: dict,
    prompt: str,
    diagnosis: dict,
    evidence: list[dict],
    auth_signals: list[dict],
    related_issues: list[dict],
    intake_config: dict,
    report_dir: Path,
    requested_state: str,
    resolved_state: str,
) -> str:
    lines = [
        MANAGED_BLOCK_START,
        "## Source Prompt",
        quote_block(prompt),
        "",
        "## Intake Diagnosis",
        f"- Project: `{project['name']}`",
        f"- Repo root: `{project['repo_root']}`",
        f"- Requested Linear state on create: `{requested_state}`",
        f"- Resolved creation state: `{resolved_state}`",
        f"- Local intake report: `{report_dir}`",
        *summarize_git_diagnosis(diagnosis),
        "",
        "## Code Evidence",
        *format_hit_lines(evidence),
        "",
        "## Authorization / Restrictions",
        *format_hit_lines(auth_signals, include_category=True),
        "",
        "## Execution Boundaries",
        *build_execution_boundaries(intake_config),
        "",
        "## Related Linear Context",
        *format_related_issues(related_issues),
        MANAGED_BLOCK_END,
    ]
    return "\n".join(lines).rstrip() + "\n"


def build_full_draft(managed_block: str, report_dir: Path) -> str:
    sections = [
        managed_block.rstrip(),
        "",
        "## Context",
        "This issue was created from a raw natural-language request and repo diagnosis.",
        "It is intended to enter the board as intake, not immediate execution.",
        "Use the evidence above to confirm scope and reduce duplicate or stale work before `Todo`.",
        "",
        "## Problem",
        "The request below needs to be reconciled with current code and board state.",
        "Right now, the operator needs a structured issue that points to the likely implementation surface and known constraints.",
        "",
        "## Desired Outcome",
        "- Confirm the requested change against current `origin/main` before it enters execution.",
        "- Scope the task to the evidenced files and surrounding modules above.",
        "- Preserve or explicitly update any auth / restriction behavior touched by the change.",
        "- Tighten acceptance criteria and validation before moving this issue to `Todo`.",
        "",
        "## Acceptance Criteria",
        "- [ ] The intended change is restated clearly against current product behavior.",
        "- [ ] The exact files or modules likely to change are confirmed from the code evidence above.",
        "- [ ] Auth / restriction boundaries are either preserved or explicitly called out for change.",
        "- [ ] Validation steps are concrete enough for a later agent or reviewer to run.",
        "- [ ] Non-goals are explicit before this issue enters `Todo`.",
        "",
        "## Validation",
        "- [ ] Re-run this intake if the prompt or target repo state changes materially.",
        "- [ ] Verify the relevant UI/system flow against the current app before execution.",
        "- [ ] Add tests, commands, screenshots, or recordings once the spec becomes agent-ready.",
        "",
        "## Assets",
        f"- Intake report bundle: `{report_dir}`",
        "- Add screenshots, mocks, PR links, or external references here if they exist.",
        "",
        "## Non-Goals",
        "- Do not move this issue directly into execution unless the spec is tightened first.",
        "- Do not ignore the auth / restriction surfaces when the task touches protected behavior.",
        "",
        "## Risks / Notes",
        "- This issue was generated from a raw prompt plus deterministic repo diagnosis.",
        "- Code evidence and restriction signals are hints, not a full semantic proof.",
        "- If the prompt changes meaningfully, supersede or revise this issue before `Todo`.",
    ]
    return "\n".join(sections).rstrip() + "\n"


def upsert_managed_block(existing_description: str, managed_block: str) -> str:
    body = existing_description or ""
    pattern = re.compile(
        re.escape(MANAGED_BLOCK_START) + r".*?" + re.escape(MANAGED_BLOCK_END),
        re.DOTALL,
    )
    if pattern.search(body):
        updated = pattern.sub(managed_block.rstrip(), body, count=1)
    elif body.strip():
        updated = managed_block.rstrip() + "\n\n" + body.strip() + "\n"
    else:
        updated = managed_block
    return updated.rstrip() + "\n"


def write_report_bundle(report_root: Path, slug: str, payload: dict, draft: str, prompt: str) -> Path:
    report_root.mkdir(parents=True, exist_ok=True)
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    report_dir = report_root / f"{timestamp}-{slug}"
    report_dir.mkdir(parents=True, exist_ok=False)
    (report_dir / "request.txt").write_text((prompt.strip() if prompt else "") + "\n", encoding="utf-8")
    (report_dir / "diagnosis.json").write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    (report_dir / "draft.md").write_text(draft, encoding="utf-8")
    return report_dir


def create_issue(
    *,
    title: str,
    description: str,
    project_context: dict,
    requested_state: str,
    requested_labels: list[str],
) -> tuple[dict, list[str]]:
    team = project_context["team"]
    state_id, resolved_state = resolve_state_id(team.get("states", {}).get("nodes", []), requested_state)
    label_ids, missing_labels = resolve_label_ids(team.get("labels", {}).get("nodes", []), requested_labels)

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

    warnings = [] if resolved_state == requested_state else [f"state:{requested_state}->{resolved_state}"]
    return created["issue"], missing_labels + warnings


def update_issue(issue_id: str, description: str, title: str | None) -> dict:
    issue_input = {"description": description}
    if title:
        issue_input["title"] = title
    data = graphql(UPDATE_ISSUE_MUTATION, {"id": issue_id, "input": issue_input})
    updated = data.get("issueUpdate", {})
    if updated.get("success") is not True:
        raise RuntimeError("issueUpdate returned success=false")
    return updated["issue"]


def main() -> int:
    args = parse_args()
    prompt = load_prompt(args)
    config = load_config(Path(os.environ["CONFIG_FILE"]))
    project = get_project(config, args.project)
    intake_config = project.get("intake", {})
    default_branch = project.get("default_branch") or config.get("defaults", {}).get("default_branch", "main")
    default_state = args.status or intake_config.get("default_state") or "Triage"
    team_key = intake_config.get("team_key")
    writable_paths = intake_config.get("writable_paths", [])
    restricted_paths = intake_config.get("restricted_paths", [])

    repo_root = Path(project["repo_root"]).expanduser()
    if not repo_root.exists():
        raise SystemExit(f"Configured repo_root does not exist: {repo_root}")

    existing_issue = fetch_issue(args.issue) if args.issue else None
    if not prompt and not existing_issue:
        raise SystemExit("Provide --prompt, --prompt-file, or stdin when drafting a new issue.")

    title = (args.title or (existing_issue or {}).get("title") or derive_title(project["name"], prompt)).strip()
    keywords = extract_keywords(f"{title}\n{prompt or ''}")
    search_roots = normalize_roots(repo_root, writable_paths)
    excluded_globs = build_excluded_globs(restricted_paths)
    diagnosis = collect_git_diagnosis(repo_root, default_branch, should_fetch=not args.no_fetch, should_sync=args.sync_main)
    linear_context = fetch_linear_context(project["linear_project_slug"], team_key)
    _, resolved_state_name = resolve_state_id(linear_context["team"].get("states", {}).get("nodes", []), default_state)
    evidence = collect_code_evidence(repo_root, search_roots, excluded_globs, search_roots, keywords, args.evidence_limit)
    auth_signals = collect_auth_signals(repo_root, search_roots, excluded_globs, args.auth_limit)
    related = select_related_issues(
        linear_context.get("issues", {}).get("nodes", []),
        keywords,
        args.related_limit,
        exclude_identifier=(existing_issue or {}).get("identifier"),
    )

    report_payload = {
        "project": {
            "name": project["name"],
            "repoRoot": str(repo_root),
            "defaultBranch": default_branch,
            "linearProjectSlug": project["linear_project_slug"],
        },
        "intakeConfig": intake_config,
        "title": title,
        "keywords": keywords,
        "gitDiagnosis": diagnosis,
        "codeEvidence": evidence,
        "authSignals": auth_signals,
        "relatedIssues": related,
    }

    report_root = Path(args.report_root).expanduser()
    report_slug = slugify(f"{project['name']}-{title}")[:80]
    placeholder_dir = report_root / "pending"
    managed_block = build_managed_block(
        project=project,
        prompt=prompt,
        diagnosis=diagnosis,
        evidence=evidence,
        auth_signals=auth_signals,
        related_issues=related,
        intake_config=intake_config,
        report_dir=placeholder_dir,
        requested_state=default_state,
        resolved_state=resolved_state_name,
    )
    placeholder_draft = build_full_draft(managed_block, placeholder_dir)
    report_dir = write_report_bundle(report_root, report_slug, report_payload, placeholder_draft, prompt)

    managed_block = build_managed_block(
        project=project,
        prompt=prompt,
        diagnosis=diagnosis,
        evidence=evidence,
        auth_signals=auth_signals,
        related_issues=related,
        intake_config=intake_config,
        report_dir=report_dir,
        requested_state=default_state,
        resolved_state=resolved_state_name,
    )
    full_draft = build_full_draft(managed_block, report_dir)
    (report_dir / "draft.md").write_text(full_draft, encoding="utf-8")

    action = "dry-run"
    linear_result = None
    warnings: list[str] = []
    rendered_description = full_draft

    if existing_issue:
        action = "refresh"
        rendered_description = upsert_managed_block(existing_issue.get("description") or "", managed_block)
        linear_result = update_issue(existing_issue["id"], rendered_description, args.title)
        (report_dir / "draft.md").write_text(rendered_description, encoding="utf-8")
        (report_dir / "linear-response.json").write_text(
            json.dumps({"issue": linear_result, "mode": "refresh"}, indent=2) + "\n",
            encoding="utf-8",
        )
    elif args.apply:
        action = "create"
        requested_labels = [item.strip() for item in args.labels.split(",") if item.strip()]
        linear_result, warnings = create_issue(
            title=title,
            description=full_draft,
            project_context=linear_context,
            requested_state=default_state,
            requested_labels=requested_labels,
        )
        (report_dir / "linear-response.json").write_text(
            json.dumps({"issue": linear_result, "warnings": warnings, "mode": "create"}, indent=2) + "\n",
            encoding="utf-8",
        )

    output = {
        "action": action,
        "project": project["name"],
        "title": title,
        "status": default_state,
        "resolvedState": resolved_state_name,
        "reportDir": str(report_dir),
        "keywords": keywords,
        "linearResult": linear_result,
        "warnings": warnings,
        "draft": rendered_description,
        "diagnosis": report_payload,
    }

    if args.json:
        print(json.dumps(output, indent=2))
        return 0

    print("Linear intake draft")
    print(f"  Project: {project['name']}")
    if resolved_state_name == default_state:
        print(f"  Status on create: {default_state}")
    else:
        print(f"  Status on create: {default_state} -> {resolved_state_name}")
    print(f"  Report bundle: {report_dir}")
    print(f"  Keywords: {', '.join(keywords) if keywords else 'none'}")
    if action == "refresh" and linear_result:
        print(f"  Refreshed issue: {linear_result['identifier']} ({linear_result['url']})")
    elif action == "create" and linear_result:
        print(f"  Created issue: {linear_result['identifier']} ({linear_result['url']})")
        if warnings:
            print(f"  Creation warnings: {', '.join(warnings)}")
    else:
        print("  Mode: dry-run (no Linear issue created)")
    print()
    print(rendered_description, end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYTHON_SCRIPT
