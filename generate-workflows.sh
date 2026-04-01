#!/usr/bin/env bash
# Generate per-project WORKFLOW.md files from template and projects.yml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/projects.yml"
TEMPLATE_FILE="${SCRIPT_DIR}/WORKFLOW.template.md"
OUTPUT_DIR="${SCRIPT_DIR}/workflows"

# Check if required tools are available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not found"
    exit 1
fi

# Generate workflows using Python (easier YAML parsing)
CONFIG_FILE="${CONFIG_FILE}" TEMPLATE_FILE="${TEMPLATE_FILE}" OUTPUT_DIR="${OUTPUT_DIR}" SCRIPT_DIR="${SCRIPT_DIR}" python3 << 'PYTHON_SCRIPT'
import yaml
import os
import textwrap
from pathlib import Path

# Read configuration
config_file = os.environ.get('CONFIG_FILE')
template_file = os.environ.get('TEMPLATE_FILE')
output_dir = os.environ.get('OUTPUT_DIR')
script_dir = os.environ.get('SCRIPT_DIR')

with open(config_file, 'r') as f:
    config = yaml.safe_load(f)

with open(template_file, 'r') as f:
    template = f.read()

workspace_root = config.get('workspace_root', f'{script_dir}/workspaces')
output_dir = config.get('workflows_dir', output_dir)
os.makedirs(output_dir, exist_ok=True)
defaults = config.get('defaults', {})

print(f"Reading config: {config_file}")
print(f"Template: {template_file}")
print(f"Output dir: {output_dir}")
print()


def indent_block(text: str) -> str:
    return textwrap.indent(text.strip('\n'), ' ' * 4)


def install_block() -> str:
    return """
# Auto-detect package manager and install dependencies
if [ -f "package.json" ]; then
  if [ -f "bun.lockb" ]; then
    bun install
  elif [ -f "pnpm-lock.yaml" ]; then
    pnpm install
  elif [ -f "yarn.lock" ]; then
    yarn install
  else
    npm install
  fi
fi

# Python projects
if [ -f "requirements.txt" ]; then
  pip install -r requirements.txt
elif [ -f "pyproject.toml" ]; then
  pip install -e .
fi

# Rust projects
if [ -f "Cargo.toml" ]; then
  cargo build
fi

# Go projects
if [ -f "go.mod" ]; then
  go mod download
fi
""".strip('\n')


def build_after_create_hook(project: dict) -> str:
    strategy = project.get('workspace_strategy', defaults.get('workspace_strategy', 'clone'))
    repo_root = project.get('repo_root', '').strip()
    default_branch = project.get('default_branch', defaults.get('default_branch', 'main'))

    if strategy == 'worktree':
        if not repo_root:
            raise SystemExit(f"project '{project['name']}' uses workspace_strategy=worktree but has no repo_root")

        return indent_block(f"""
MAIN_REPO="{repo_root}"
WORKSPACE="$(pwd)"
ISSUE_ID="$(basename "$WORKSPACE")"
BRANCH="feature/${{ISSUE_ID}}"

cd "$MAIN_REPO" && git fetch origin

# Remove the empty workspace dir Symphony created, then replace it with a git worktree.
rmdir "$WORKSPACE"
git worktree add "$WORKSPACE" -b "$BRANCH" origin/{default_branch}

cd "$WORKSPACE"

{install_block()}
""")

    return indent_block(f"""
git clone --depth 1 --branch {default_branch} {project['github_url']} .

{install_block()}
""")


def build_before_remove_hook(project: dict) -> str:
    strategy = project.get('workspace_strategy', defaults.get('workspace_strategy', 'clone'))
    repo_root = project.get('repo_root', '').strip()

    if strategy == 'worktree':
        if not repo_root:
            raise SystemExit(f"project '{project['name']}' uses workspace_strategy=worktree but has no repo_root")

        return indent_block(f"""
MAIN_REPO="{repo_root}"
WORKSPACE="$(pwd)"
cd "$MAIN_REPO" 2>/dev/null && git worktree remove "$WORKSPACE" --force 2>/dev/null || true
git worktree prune 2>/dev/null || true
""")

    return indent_block(f"""
# Cleanup hook - runs before workspace deletion
echo "Cleaning up workspace for {project['name']}"
""")


def load_appendix(project: dict) -> str:
    appendix_path = project.get('workflow_appendix', '').strip()
    if not appendix_path:
        return ''

    appendix_file = Path(script_dir) / appendix_path
    return "\n" + appendix_file.read_text().rstrip() + "\n"

# Generate workflow for each project
count = 0
for project in config['projects']:
    project_name = project['name']
    github_url = project['github_url']
    repo_root = project.get('repo_root', '').strip()
    linear_slug = project['linear_project_slug']
    workspace_path = f"{workspace_root}/{project_name}"
    after_create_hook = build_after_create_hook(project)
    before_remove_hook = build_before_remove_hook(project)
    max_agents = project.get('max_agents', defaults.get('max_agents', 2))
    max_turns = project.get('max_turns', defaults.get('max_turns', 20))
    polling_interval = project.get('polling_interval_ms', defaults.get('polling_interval_ms', 5000))
    workspace_strategy = project.get('workspace_strategy', defaults.get('workspace_strategy', 'clone'))
    default_branch = project.get('default_branch', defaults.get('default_branch', 'main'))
    appendix = load_appendix(project)

    # Substitute placeholders
    workflow_content = template.replace('{{LINEAR_PROJECT_SLUG}}', linear_slug)
    workflow_content = workflow_content.replace('{{GITHUB_URL}}', github_url)
    workflow_content = workflow_content.replace('{{WORKSPACE_PATH}}', workspace_path)
    workflow_content = workflow_content.replace('{{PROJECT_NAME}}', project_name)
    workflow_content = workflow_content.replace('{{REPO_ROOT}}', repo_root or '(ephemeral clone checkout)')
    workflow_content = workflow_content.replace('{{WORKSPACE_STRATEGY}}', workspace_strategy)
    workflow_content = workflow_content.replace('{{DEFAULT_BRANCH}}', default_branch)
    workflow_content = workflow_content.replace('{{POLLING_INTERVAL_MS}}', str(polling_interval))
    workflow_content = workflow_content.replace('{{MAX_CONCURRENT_AGENTS}}', str(max_agents))
    workflow_content = workflow_content.replace('{{MAX_TURNS}}', str(max_turns))
    workflow_content = workflow_content.replace('{{AFTER_CREATE_HOOK}}', after_create_hook)
    workflow_content = workflow_content.replace('{{BEFORE_REMOVE_HOOK}}', before_remove_hook)
    workflow_content = workflow_content.replace('{{PROJECT_APPENDIX}}', appendix)
    workflow_content = workflow_content.rstrip() + "\n"

    # Write output file
    output_file = f"{output_dir}/{project_name}.WORKFLOW.md"
    with open(output_file, 'w') as f:
        f.write(workflow_content)

    print(f"  ✅    {project_name} → {output_file}")
    count += 1

print(f"\nGenerated {count} workflow file(s)")
PYTHON_SCRIPT

echo "Done!"
