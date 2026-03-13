#!/usr/bin/env bash
# Generate per-project WORKFLOW.md files from template and projects.yml
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/projects.yml"
TEMPLATE_FILE="${SCRIPT_DIR}/WORKFLOW.template.md"
OUTPUT_DIR="${SCRIPT_DIR}/workflows"

echo "Reading config: ${CONFIG_FILE}"
echo "Template: ${TEMPLATE_FILE}"
echo "Output dir: ${OUTPUT_DIR}"
echo

# Ensure output directory exists
mkdir -p "${OUTPUT_DIR}"

# Check if required tools are available
if ! command -v python3 &> /dev/null; then
    echo "Error: python3 is required but not found"
    exit 1
fi

# Generate workflows using Python (easier YAML parsing)
CONFIG_FILE="${CONFIG_FILE}" TEMPLATE_FILE="${TEMPLATE_FILE}" OUTPUT_DIR="${OUTPUT_DIR}" SCRIPT_DIR="${SCRIPT_DIR}" python3 << 'PYTHON_SCRIPT'
import yaml
import sys
import os

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

# Generate workflow for each project
count = 0
for project in config['projects']:
    project_name = project['name']
    github_url = project['github_url']
    linear_slug = project['linear_project_slug']
    workspace_path = f"{workspace_root}/{project_name}"

    # Substitute placeholders
    workflow_content = template.replace('{{LINEAR_PROJECT_SLUG}}', linear_slug)
    workflow_content = workflow_content.replace('{{GITHUB_URL}}', github_url)
    workflow_content = workflow_content.replace('{{WORKSPACE_PATH}}', workspace_path)
    workflow_content = workflow_content.replace('{{PROJECT_NAME}}', project_name)

    # Write output file
    output_file = f"{output_dir}/{project_name}.WORKFLOW.md"
    with open(output_file, 'w') as f:
        f.write(workflow_content)

    print(f"  ✅    {project_name} → {output_file}")
    count += 1

print(f"\nGenerated {count} workflow file(s)")
PYTHON_SCRIPT

echo "Done!"
