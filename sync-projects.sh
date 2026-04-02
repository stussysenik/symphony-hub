#!/usr/bin/env bash
# sync-projects.sh - Sync GitHub repo metadata into the Symphony project catalog.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/projects.yml"

export SCRIPT_DIR CONFIG_FILE
python3 - "$@" <<'PYTHON_SCRIPT'
from __future__ import annotations

import argparse
import copy
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.environ["SCRIPT_DIR"])
from project_catalog import catalog_projects, catalog_section, load_config, managed_projects, normalize_repo_slug, save_config

DEFAULT_REPORT_ROOT = Path(os.environ["SCRIPT_DIR"]) / "syncs"
DEFAULT_LIMIT = 500
GENERIC_INTAKE = {
    "team_key": "CRE",
    "default_state": "Triage",
    "writable_paths": [],
    "restricted_paths": [".git", "node_modules", ".next", "dist", "coverage", ".turbo"],
    "required_checks": [],
    "notes": [
        "Imported from GitHub catalog sync; refine writable paths, checks, and scope before agent execution.",
        "Do not move this repo into active runtime flows until the Linear mapping and local clone are verified.",
    ],
}
GENERIC_ASSETS = {
    "collect_attachments": True,
    "scan_project_dirs": True,
    "capture_screenshots": False,
    "supported_formats": ["png", "jpg", "gif", "webp", "svg", "figma"],
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        prog="./sync-projects.sh",
        description="Sync GitHub repositories into the Symphony repo catalog.",
    )
    parser.add_argument("--owner", help="GitHub owner/org to sync. Defaults to catalog.github_owner or the first configured repo owner.")
    parser.add_argument("--limit", type=int, default=DEFAULT_LIMIT, help="Maximum repos to fetch from GitHub.")
    parser.add_argument("--visibility", choices=["all", "public", "private"], default="all", help="GitHub visibility filter.")
    parser.add_argument("--include-forks", action="store_true", help="Keep forked repositories in the synced catalog.")
    parser.add_argument("--include-archived", action="store_true", help="Keep archived repositories in the synced catalog.")
    parser.add_argument("--clone-missing", action="store_true", help="Clone missing local repos during apply so repo-backed diagnosis can run immediately.")
    parser.add_argument("--exclude-repo-slug", action="append", dest="exclude_repo_slugs", help="Repo slug to exclude from this run. Repeatable.")
    parser.add_argument("--repo-root-parent", help="Local parent directory used to infer repo_root values.")
    parser.add_argument("--linear-project-slug", help="Default Linear project slug for newly cataloged repos.")
    parser.add_argument("--team-key", help="Default intake.team_key for newly cataloged repos.")
    parser.add_argument("--default-state", help="Default intake.default_state for newly cataloged repos.")
    parser.add_argument("--report-root", default=str(DEFAULT_REPORT_ROOT), help="Local sync report directory root.")
    parser.add_argument("--apply", action="store_true", help="Write the merged catalog back to projects.yml. Dry-run by default.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    return parser.parse_args()


def run_command(args: list[str]) -> subprocess.CompletedProcess[str]:
    return subprocess.run(args, text=True, capture_output=True, check=False)


def ensure_gh_available() -> None:
    result = run_command(["gh", "--version"])
    if result.returncode != 0:
        raise SystemExit("GitHub CLI 'gh' is required for sync-projects.")
    auth = run_command(["gh", "auth", "status"])
    if auth.returncode != 0:
        stderr = auth.stderr.strip() or auth.stdout.strip()
        raise SystemExit(f"gh auth status failed: {stderr}")


def infer_owner(config: dict) -> str:
    catalog = catalog_section(config)
    owner = (catalog.get("github_owner") or "").strip()
    if owner:
        return owner
    for project in managed_projects(config):
        slug = normalize_repo_slug(project.get("github_url", ""))
        if "/" in slug:
            return slug.split("/", 1)[0]
    raise SystemExit("Unable to infer GitHub owner. Pass --owner or set catalog.github_owner in projects.yml.")


def infer_repo_root_parent(config: dict) -> str:
    catalog = catalog_section(config)
    parent = (catalog.get("repo_root_parent") or "").strip()
    if parent:
        return parent
    for project in managed_projects(config):
        repo_root = (project.get("repo_root") or "").strip()
        if repo_root:
            return str(Path(repo_root).expanduser().parent)
    return str(Path("~/Desktop").expanduser())


def infer_catalog_defaults(config: dict) -> dict:
    catalog = catalog_section(config)
    defaults = catalog.get("defaults")
    if isinstance(defaults, dict):
        return copy.deepcopy(defaults)
    return {}


def ensure_catalog_defaults(config: dict, *, repo_root_parent: str, linear_project_slug: str, team_key: str, default_state: str) -> dict:
    catalog = catalog_section(config)
    defaults = infer_catalog_defaults(config)
    defaults.setdefault("max_agents", config.get("defaults", {}).get("max_agents", 2))
    defaults.setdefault("workspace_strategy", config.get("defaults", {}).get("workspace_strategy", "worktree"))
    defaults.setdefault("linear_project_slug", linear_project_slug)
    intake = defaults.get("intake")
    if not isinstance(intake, dict):
        intake = copy.deepcopy(GENERIC_INTAKE)
    else:
        intake = copy.deepcopy(intake)
    intake.setdefault("team_key", team_key)
    intake.setdefault("default_state", default_state)
    intake.setdefault("writable_paths", [])
    intake.setdefault("restricted_paths", copy.deepcopy(GENERIC_INTAKE["restricted_paths"]))
    intake.setdefault("required_checks", [])
    intake.setdefault("notes", copy.deepcopy(GENERIC_INTAKE["notes"]))
    defaults["intake"] = intake
    assets = defaults.get("assets")
    if not isinstance(assets, dict):
        assets = copy.deepcopy(GENERIC_ASSETS)
    else:
        assets = copy.deepcopy(assets)
    assets.setdefault("collect_attachments", True)
    assets.setdefault("scan_project_dirs", True)
    assets.setdefault("capture_screenshots", False)
    assets.setdefault("supported_formats", copy.deepcopy(GENERIC_ASSETS["supported_formats"]))
    defaults["assets"] = assets
    catalog["repo_root_parent"] = repo_root_parent
    catalog["defaults"] = defaults
    return defaults


def fetch_repositories(owner: str, limit: int, visibility: str) -> list[dict]:
    cmd = [
        "gh",
        "repo",
        "list",
        owner,
        "--limit",
        str(limit),
        "--json",
        "name,nameWithOwner,url,sshUrl,isPrivate,isFork,isArchived,defaultBranchRef",
    ]
    if visibility != "all":
        cmd.extend(["--visibility", visibility])
    result = run_command(cmd)
    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip()
        raise SystemExit(f"gh repo list failed: {stderr}")
    return json.loads(result.stdout)


def create_run_dir(report_root: Path, owner: str) -> Path:
    timestamp = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%SZ")
    run_dir = report_root / f"{timestamp}-sync-{owner}"
    suffix = 1
    while run_dir.exists():
        run_dir = report_root / f"{timestamp}-sync-{owner}-{suffix}"
        suffix += 1
    run_dir.mkdir(parents=True, exist_ok=False)
    return run_dir


def regenerate_workflows(script_dir: Path) -> None:
    result = run_command(["bash", str(script_dir / "generate-workflows.sh")])
    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip()
        raise SystemExit(f"generate-workflows.sh failed: {stderr}")


def ensure_git_url(url: str) -> str:
    return url if url.endswith(".git") else f"{url}.git"


def infer_repo_root(repo_root_parent: str, repo_name: str) -> str:
    return str(Path(repo_root_parent).expanduser() / repo_name)


def clone_repo(github_slug: str, repo_root: str) -> None:
    target = Path(repo_root).expanduser()
    target.parent.mkdir(parents=True, exist_ok=True)
    result = run_command(["gh", "repo", "clone", github_slug, str(target)])
    if result.returncode != 0:
        stderr = result.stderr.strip() or result.stdout.strip()
        raise SystemExit(f"gh repo clone failed for {github_slug}: {stderr}")


def merge_sync_metadata(project: dict, repo: dict, owner: str, synced_at: str) -> None:
    sync = project.get("sync")
    if not isinstance(sync, dict):
        sync = {}
    sync["source"] = "github"
    sync["owner"] = owner
    sync["github_slug"] = repo["nameWithOwner"]
    sync["private"] = bool(repo["isPrivate"])
    sync["archived"] = bool(repo["isArchived"])
    sync.setdefault("synced_at", synced_at)
    project["sync"] = sync


def build_catalog_entry(repo: dict, defaults: dict, repo_root_parent: str, synced_at: str, owner: str, linear_project_slug: str) -> dict:
    entry = {
        "name": repo["name"],
        "github_slug": repo["nameWithOwner"],
        "github_url": ensure_git_url(repo["url"]),
        "repo_root": infer_repo_root(repo_root_parent, repo["name"]),
        "linear_project_slug": linear_project_slug,
        "max_agents": defaults.get("max_agents", 2),
        "default_branch": ((repo.get("defaultBranchRef") or {}).get("name") or "main"),
        "workspace_strategy": defaults.get("workspace_strategy", "worktree"),
        "managed": False,
        "intake": copy.deepcopy(defaults["intake"]),
        "assets": copy.deepcopy(defaults["assets"]),
    }
    merge_sync_metadata(entry, repo, owner, synced_at)
    return entry


def maybe_update_managed_project(project: dict, repo: dict, owner: str, synced_at: str) -> None:
    project["github_slug"] = repo["nameWithOwner"]
    project["github_url"] = ensure_git_url(repo["url"])
    project["default_branch"] = ((repo.get("defaultBranchRef") or {}).get("name") or project.get("default_branch") or "main")
    merge_sync_metadata(project, repo, owner, synced_at)


def maybe_update_catalog_project(project: dict, repo: dict, owner: str, synced_at: str, repo_root_parent: str, linear_project_slug: str) -> None:
    project["name"] = repo["name"]
    project["github_slug"] = repo["nameWithOwner"]
    project["github_url"] = ensure_git_url(repo["url"])
    project["default_branch"] = ((repo.get("defaultBranchRef") or {}).get("name") or project.get("default_branch") or "main")
    if not (project.get("repo_root") or "").strip():
        project["repo_root"] = infer_repo_root(repo_root_parent, repo["name"])
    if not (project.get("linear_project_slug") or "").strip() and linear_project_slug:
        project["linear_project_slug"] = linear_project_slug
    project["managed"] = False
    merge_sync_metadata(project, repo, owner, synced_at)


def render_summary(output: dict) -> str:
    lines = [
        "Symphony Project Catalog Sync",
        f"Generated: {datetime.now().astimezone().strftime('%Y-%m-%d %H:%M:%S %Z')}",
        f"Mode: {output['mode']}",
        f"Owner: {output['owner']}",
        f"Report bundle: {output['reportDir']}",
        "",
        "Counts:",
        f"- fetched: {output['fetchedCount']}",
        f"- managed_updated: {output['managedUpdated']}",
        f"- catalog_added: {output['catalogAdded']}",
        f"- catalog_updated: {output['catalogUpdated']}",
        f"- cloned: {output['clonedCount']}",
        f"- skipped: {output['skippedCount']}",
        "",
        "Results:",
    ]
    for item in output["results"]:
        line = f"- {item['githubSlug']}: {item['action']}"
        if item.get("repoRoot"):
            line += f" -> {item['repoRoot']}"
            if item.get("repoRootExists") is not None:
                line += " [local]" if item["repoRootExists"] else " [missing]"
        if item.get("wouldClone"):
            line += " [would-clone]"
        lines.append(line)
    return "\n".join(lines).rstrip() + "\n"


def main() -> int:
    args = parse_args()
    ensure_gh_available()

    config_path = Path(os.environ["CONFIG_FILE"])
    config = load_config(config_path)
    owner = (args.owner or infer_owner(config)).strip()
    repo_root_parent = (args.repo_root_parent or infer_repo_root_parent(config)).strip()
    seeded_linear_slug = (args.linear_project_slug or "").strip()
    catalog = catalog_section(config)
    include_forks = bool(args.include_forks or catalog.get("include_forks"))
    include_archived = bool(args.include_archived or catalog.get("include_archived"))
    clone_missing = bool(args.clone_missing or catalog.get("clone_missing"))
    excluded = {
        normalize_repo_slug(item).lower()
        for item in (catalog.get("excluded_repo_slugs") or []) + (args.exclude_repo_slugs or [])
        if normalize_repo_slug(item)
    }
    defaults = ensure_catalog_defaults(
        config,
        repo_root_parent=repo_root_parent,
        linear_project_slug=seeded_linear_slug,
        team_key=(args.team_key or GENERIC_INTAKE["team_key"]).strip(),
        default_state=(args.default_state or GENERIC_INTAKE["default_state"]).strip(),
    )

    all_repos = fetch_repositories(owner, args.limit, args.visibility)
    repos = all_repos
    if not include_archived:
        repos = [repo for repo in repos if not repo.get("isArchived")]
    if not include_forks:
        repos = [repo for repo in repos if not repo.get("isFork")]
    repos = [repo for repo in repos if repo["nameWithOwner"].lower() not in excluded]

    synced_at = datetime.now(timezone.utc).isoformat()
    managed = managed_projects(config)
    managed_by_slug = {
        normalize_repo_slug(project.get("github_url", "")).lower(): project
        for project in managed
        if normalize_repo_slug(project.get("github_url", ""))
    }
    catalog = catalog_projects(config)
    catalog_by_slug = {
        normalize_repo_slug(project.get("github_url", "")).lower(): project
        for project in catalog
        if normalize_repo_slug(project.get("github_url", ""))
    }

    results = []
    managed_updated = 0
    catalog_added = 0
    catalog_updated = 0
    cloned = 0
    skipped = len(all_repos) - len(repos)

    for repo in repos:
        github_slug = repo["nameWithOwner"]
        slug_key = github_slug.lower()
        managed_project = managed_by_slug.get(slug_key)
        repo_root = infer_repo_root(repo_root_parent, repo["name"])
        resolved_root = Path((managed_project or catalog_by_slug.get(slug_key) or {}).get("repo_root", repo_root)).expanduser()
        repo_root_exists = resolved_root.exists()
        would_clone = clone_missing and not repo_root_exists
        if args.apply and would_clone:
            clone_repo(github_slug, str(resolved_root))
            repo_root_exists = True
            cloned += 1
        if managed_project:
            maybe_update_managed_project(managed_project, repo, owner, synced_at)
            managed_updated += 1
            results.append(
                {
                    "githubSlug": github_slug,
                    "action": "updated_managed",
                    "project": managed_project["name"],
                    "repoRoot": managed_project.get("repo_root"),
                    "repoRootExists": Path(managed_project.get("repo_root", "")).expanduser().exists() if managed_project.get("repo_root") else None,
                    "wouldClone": would_clone and not args.apply,
                }
            )
            continue

        catalog_project = catalog_by_slug.get(slug_key)
        if catalog_project:
            maybe_update_catalog_project(catalog_project, repo, owner, synced_at, repo_root_parent, seeded_linear_slug or defaults.get("linear_project_slug", ""))
            catalog_updated += 1
            results.append(
                {
                    "githubSlug": github_slug,
                    "action": "updated_catalog",
                    "project": catalog_project["name"],
                    "repoRoot": catalog_project.get("repo_root"),
                    "repoRootExists": Path(catalog_project.get("repo_root", "")).expanduser().exists() if catalog_project.get("repo_root") else None,
                    "wouldClone": would_clone and not args.apply,
                }
            )
            continue

        entry = build_catalog_entry(
            repo,
            defaults=defaults,
            repo_root_parent=repo_root_parent,
            synced_at=synced_at,
            owner=owner,
            linear_project_slug=seeded_linear_slug or defaults.get("linear_project_slug", ""),
        )
        catalog.append(entry)
        catalog_added += 1
        results.append(
            {
                "githubSlug": github_slug,
                "action": "added_catalog",
                "project": entry["name"],
                "repoRoot": entry["repo_root"],
                "repoRootExists": Path(entry["repo_root"]).expanduser().exists(),
                "wouldClone": would_clone and not args.apply,
            }
        )

    catalog.sort(key=lambda item: (item.get("github_slug") or normalize_repo_slug(item.get("github_url", ""))).lower())
    catalog_meta = catalog_section(config)
    catalog_meta["github_owner"] = owner
    catalog_meta["last_sync_at"] = synced_at
    catalog_meta["last_sync_count"] = len(repos)

    report_root = Path(args.report_root).expanduser()
    run_dir = create_run_dir(report_root, owner.replace("/", "-"))

    output = {
        "mode": "apply" if args.apply else "dry-run",
        "owner": owner,
        "reportDir": str(run_dir),
        "fetchedCount": len(repos),
        "managedUpdated": managed_updated,
        "catalogAdded": catalog_added,
        "catalogUpdated": catalog_updated,
        "clonedCount": cloned,
        "skippedCount": skipped,
        "results": results,
    }

    if args.apply:
        save_config(config_path, config)
        if managed_updated:
            regenerate_workflows(Path(os.environ["SCRIPT_DIR"]))

    (run_dir / "summary.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")
    (run_dir / "SUMMARY.md").write_text(render_summary(output), encoding="utf-8")

    if args.json:
        print(json.dumps(output, indent=2))
    else:
        print(render_summary(output), end="")
    return 0


if __name__ == "__main__":
    sys.exit(main())
PYTHON_SCRIPT
