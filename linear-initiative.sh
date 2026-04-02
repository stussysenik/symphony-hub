#!/usr/bin/env bash
# linear-initiative.sh - Fan out one initiative prompt across multiple configured repos.

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
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.environ["SCRIPT_DIR"])
from project_catalog import all_projects, load_config, normalize_repo_slug

DEFAULT_REPORT_ROOT = Path(os.environ["SCRIPT_DIR"]) / "initiatives"


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="./linear-initiative.sh",
        description="Fan out one initiative prompt across multiple configured Symphony projects."
    )
    parser.add_argument("--all", action="store_true", help="Target all configured projects.")
    parser.add_argument("--project", action="append", dest="projects", help="Configured project name to target. Repeatable.")
    parser.add_argument("--repo-slug", action="append", dest="repo_slugs", help="GitHub repo slug like owner/repo. Repeatable.")
    parser.add_argument("--prompt", help="Shared initiative prompt.")
    parser.add_argument("--prompt-file", help="Path to a file containing the shared initiative prompt.")
    parser.add_argument("--system-prompt", help="Optional shared operator guidance appended to every repo-local issue request.")
    parser.add_argument("--system-prompt-file", help="Path to a file containing the shared system prompt.")
    parser.add_argument("--title-prefix", help="Optional per-repo title prefix, e.g. 'Adopt Nix dev shell'.")
    parser.add_argument("--linear-project-slug", help="Override the configured Linear project slug for every targeted repo.")
    parser.add_argument("--labels", default="", help="Comma-separated label names forwarded to each intake run.")
    parser.add_argument("--status", default="Triage", help="Initial state for created issues; defaults to Triage.")
    parser.add_argument("--apply", action="store_true", help="Create the repo-local Linear issues. Dry-run by default.")
    parser.add_argument("--no-fetch", action="store_true", help="Skip git fetch in downstream intake runs.")
    parser.add_argument("--model", help="Optional Codex model override forwarded to intake.")
    parser.add_argument("--report-root", default=str(DEFAULT_REPORT_ROOT), help="Local initiative report directory root.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    return parser.parse_args()


def load_text(value: str | None, path: str | None, stdin_path: str | None = None, *, required: bool = False, field_name: str) -> str:
    stdin_text = ""
    if stdin_path and Path(stdin_path).exists():
        stdin_text = Path(stdin_path).read_text(encoding="utf-8").strip()
    provided = [bool(value), bool(path), bool(stdin_text)]
    if sum(provided) > 1:
        raise SystemExit(f"Use only one of --{field_name}, --{field_name}-file, or stdin.")
    if value:
        return value.strip()
    if path:
        return Path(path).read_text(encoding="utf-8").strip()
    if stdin_text:
        return stdin_text
    if required:
        raise SystemExit(f"Provide --{field_name}, --{field_name}-file, or pipe the text on stdin.")
    return ""
def slugify(value: str) -> str:
    slug = re.sub(r"[^a-z0-9]+", "-", value.lower()).strip("-")
    return slug or "initiative"


def select_projects(config: dict, args: argparse.Namespace) -> list[dict]:
    configured = all_projects(config)
    if args.all:
        return configured

    requested_projects = set(args.projects or [])
    requested_slugs = {item.lower() for item in (args.repo_slugs or [])}
    if not requested_projects and not requested_slugs:
        raise SystemExit("Pass --all, --project <name>, or --repo-slug <owner/repo>.")

    selected: list[dict] = []
    missing_projects = set(requested_projects)
    missing_slugs = set(requested_slugs)
    for project in configured:
        project_name = project.get("name", "")
        project_slug = normalize_repo_slug(project.get("github_url", "")).lower()
        if project_name in requested_projects or project_slug in requested_slugs:
            selected.append(project)
            missing_projects.discard(project_name)
            missing_slugs.discard(project_slug)

    if missing_projects:
        raise SystemExit(f"Configured projects not found: {', '.join(sorted(missing_projects))}")
    if missing_slugs:
        raise SystemExit(f"Configured repo slugs not found: {', '.join(sorted(missing_slugs))}")
    return selected


def build_repo_task(shared_prompt: str, system_prompt: str, project: dict, github_slug: str) -> str:
    parts = [
        "You are turning a cross-repo initiative into one repo-local execution issue.",
        "",
        "Shared initiative request:",
        shared_prompt,
        "",
        "Target repository:",
        f"- Symphony project: {project['name']}",
        f"- GitHub slug: {github_slug}",
        f"- Repo root: {project['repo_root']}",
        f"- Default branch: {project.get('default_branch', 'main')}",
        "",
        "Instructions:",
        "- Keep the issue specific to this repository only.",
        "- Do not write an umbrella issue here.",
        "- Use the repo diagnosis to tailor the acceptance criteria and validation to this repository.",
        "- Preserve history; do not delete prior workflow context.",
    ]
    if system_prompt:
        parts.extend(
            [
                "",
                "Shared operator guidance:",
                system_prompt,
            ]
        )
    return "\n".join(parts).strip()


def run_intake(script_path: Path, project: dict, task: str, args: argparse.Namespace, report_root: Path) -> dict:
    cmd = [
        "bash",
        str(script_path),
        "--project",
        project["name"],
        "--task",
        task,
        "--status",
        args.status,
        "--report-root",
        str(report_root),
        "--json",
    ]
    if args.title_prefix:
        cmd.extend(["--title", f"{project['name']}: {args.title_prefix}"])
    if args.linear_project_slug:
        cmd.extend(["--linear-project-slug", args.linear_project_slug])
    if args.labels.strip():
        cmd.extend(["--labels", args.labels.strip()])
    if args.apply:
        cmd.append("--apply")
    if args.no_fetch:
        cmd.append("--no-fetch")
    if args.model:
        cmd.extend(["--model", args.model])

    result = subprocess.run(cmd, text=True, capture_output=True)
    if result.returncode != 0:
        raise RuntimeError(
            f"linear-intake failed for {project['name']}.\n"
            f"stdout:\n{result.stdout}\n\nstderr:\n{result.stderr}"
        )
    return json.loads(result.stdout)


def create_run_dir(report_root: Path, initiative_slug: str) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    base = report_root / f"{timestamp}-{initiative_slug}"
    candidate = base
    suffix = 1
    while candidate.exists():
        candidate = report_root / f"{timestamp}-{initiative_slug}-{suffix}"
        suffix += 1
    candidate.mkdir(parents=True, exist_ok=False)
    return candidate


def render_summary(output: dict) -> str:
    lines = [
        "Symphony Initiative Fanout",
        f"Generated: {datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')}",
        f"Mode: {output['mode']}",
        f"Report bundle: {output['reportDir']}",
        "",
        "Targets:",
    ]
    for result in output["results"]:
        prefix = f"- {result['project']} ({result['githubSlug']})"
        if result["status"] == "ok":
            issue = result.get("createdIssue")
            if issue:
                lines.append(f"{prefix}: {issue['identifier']} -> {issue['url']}")
            else:
                lines.append(f"{prefix}: draft '{result['title']}' -> {result['recommendedState']}")
            lines.append(f"  compile={result['compileMode']}, report={result['reportDir']}")
        else:
            lines.append(f"{prefix}: ERROR")
            lines.append(f"  {result['error']}")
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    args = parse_args()
    config = load_config(Path(os.environ["CONFIG_FILE"]))
    prompt = load_text(args.prompt, args.prompt_file, os.environ.get("STDIN_CAPTURE"), required=True, field_name="prompt")
    system_prompt = load_text(args.system_prompt, args.system_prompt_file, required=False, field_name="system-prompt")
    selected_projects = select_projects(config, args)

    initiative_slug = slugify(args.title_prefix or prompt[:80])
    run_dir = create_run_dir(Path(args.report_root).expanduser(), initiative_slug)
    intake_report_root = run_dir / "intakes"
    intake_script = Path(os.environ["SCRIPT_DIR"]) / "linear-intake.sh"

    results = []
    failures = 0
    for project in selected_projects:
        github_slug = normalize_repo_slug(project.get("github_url", ""))
        task = build_repo_task(prompt, system_prompt, project, github_slug)
        try:
            resolved_linear_slug = (args.linear_project_slug or project.get("linear_project_slug") or "").strip()
            repo_root = Path(project.get("repo_root", "")).expanduser()
            if not resolved_linear_slug:
                raise RuntimeError(
                    "Missing linear_project_slug. Provide --linear-project-slug or map the repo in projects.yml."
                )
            if not repo_root.exists():
                raise RuntimeError(f"Configured repo_root does not exist: {repo_root}")
            intake_output = run_intake(intake_script, project, task, args, intake_report_root)
            result = {
                "project": project["name"],
                "githubSlug": github_slug,
                "repoRoot": project["repo_root"],
                "linearProjectSlug": resolved_linear_slug,
                "status": "ok",
                "title": intake_output["title"],
                "recommendedState": intake_output["recommendedState"],
                "compileMode": intake_output["compileMode"],
                "reportDir": intake_output["reportDir"],
                "createdIssue": intake_output["createdIssue"],
                "task": task,
            }
            (run_dir / f"{project['name']}.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
            results.append(result)
        except Exception as exc:  # noqa: BLE001
            failures += 1
            result = {
                "project": project["name"],
                "githubSlug": github_slug,
                "repoRoot": project["repo_root"],
                "status": "error",
                "error": str(exc),
            }
            (run_dir / f"{project['name']}.error.txt").write_text(str(exc).rstrip() + "\n", encoding="utf-8")
            results.append(result)

    output = {
        "mode": "apply" if args.apply else "dry-run",
        "initiativePrompt": prompt,
        "systemPrompt": system_prompt,
        "reportDir": str(run_dir),
        "count": len(results),
        "failureCount": failures,
        "results": results,
    }
    (run_dir / "summary.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    (run_dir / "SUMMARY.md").write_text(render_summary(output), encoding="utf-8")

    if args.json:
        print(json.dumps(output, indent=2))
    else:
        print(render_summary(output), end="")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
PYTHON_SCRIPT
