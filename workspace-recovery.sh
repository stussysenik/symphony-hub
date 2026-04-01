#!/usr/bin/env bash
# workspace-recovery.sh - Inspect preserved workspaces for recovery/archival decisions.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

PROJECT=""
ROOT=""
ISSUE_FILTER=""

usage() {
    cat <<'EOF'
Usage:
  ./workspace-recovery.sh --project <name> [options]

Options:
  --project <name>    Configured project name (required)
  --root <dir>        Workspace root to inspect (default: configured workspace_root)
  --issue <ID>        Only inspect one issue workspace
  --help              Show this help text

Examples:
  ./workspace-recovery.sh --project mymind-clone-web
  ./workspace-recovery.sh --project mymind-clone-web --root /Users/s3nik/Desktop/symphony-setup/workspaces
  ./workspace-recovery.sh --project mymind-clone-web --root /Users/s3nik/Desktop/symphony-setup/workspaces --issue CRE-8
EOF
}

while [ $# -gt 0 ]; do
    case "$1" in
        --project)
            PROJECT="${2:-}"
            shift 2
            ;;
        --root)
            ROOT="${2:-}"
            shift 2
            ;;
        --issue)
            ISSUE_FILTER="${2:-}"
            shift 2
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

if [ -z "${PROJECT}" ]; then
    echo "Error: --project is required" >&2
    usage
    exit 1
fi

if [ -z "${ROOT}" ]; then
    ROOT="$(symphony_config_get "workspace_root")"
fi

export PROJECT ROOT ISSUE_FILTER
python3 <<'PYTHON_SCRIPT'
import json
import os
import subprocess
from pathlib import Path


def run(cmd, cwd=None):
    result = subprocess.run(cmd, cwd=cwd, capture_output=True, text=True)
    return result.returncode, result.stdout.strip(), result.stderr.strip()


project = os.environ["PROJECT"]
root = Path(os.environ["ROOT"]).expanduser()
issue_filter = os.environ.get("ISSUE_FILTER", "").strip()
project_root = root / project

if not project_root.exists():
    raise SystemExit(f"Workspace root not found: {project_root}")

workspace_dirs = []
for child in sorted(project_root.iterdir()):
    if not child.is_dir():
        continue
    if issue_filter and child.name != issue_filter:
        continue
    workspace_dirs.append(child)

print("Workspace Recovery Report")
print(f"Project: {project}")
print(f"Root: {project_root}")
print(f"Count: {len(workspace_dirs)}")
print()

for ws in workspace_dirs:
    code, branch, _ = run(["git", "branch", "--show-current"], cwd=ws)
    branch = branch or "unknown"

    code, status, _ = run(["git", "status", "--short"], cwd=ws)
    dirty_lines = [line for line in status.splitlines() if line.strip()]
    tracked_dirty = sum(1 for line in dirty_lines if not line.startswith("??"))
    untracked = sum(1 for line in dirty_lines if line.startswith("??"))

    code, head, _ = run(["git", "log", "--oneline", "-1"], cwd=ws)
    if not head:
        head = "no commits"

    code, remote_check, _ = run(["git", "ls-remote", "--heads", "origin", branch], cwd=ws)
    remote_exists = bool(remote_check.strip())

    progress_path = ws / "PROGRESS.md"
    learning_path = ws / "LEARNING.md"
    screenshots_path = ws / "pr-screenshots"

    print(f"{ws.name}")
    print(f"  Path: {ws}")
    print(f"  Branch: {branch}")
    print(f"  Dirty tracked files: {tracked_dirty}")
    print(f"  Untracked files: {untracked}")
    print(f"  Remote branch exists: {'yes' if remote_exists else 'no'}")
    print(f"  HEAD: {head}")
    print(f"  PROGRESS.md: {'yes' if progress_path.exists() else 'no'}")
    print(f"  LEARNING.md: {'yes' if learning_path.exists() else 'no'}")
    print(f"  pr-screenshots/: {'yes' if screenshots_path.exists() else 'no'}")
    print()
PYTHON_SCRIPT
