#!/usr/bin/env bash

SYMPHONY_ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SYMPHONY_CONFIG_FILE="${SYMPHONY_CONFIG_FILE:-${SYMPHONY_ROOT_DIR}/projects.yml}"

symphony_require_python() {
    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required but not found" >&2
        return 1
    fi
}

symphony_config_get() {
    local key=$1
    symphony_require_python || return 1

    CONFIG_FILE="${SYMPHONY_CONFIG_FILE}" KEY="${key}" python3 <<'PY'
import os
import sys
import yaml

config_file = os.environ["CONFIG_FILE"]
key = os.environ["KEY"]

with open(config_file, "r", encoding="utf-8") as handle:
    config = yaml.safe_load(handle) or {}

value = config
for part in key.split("."):
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        value = ""
        break

if value is None:
    value = ""

print(value)
PY
}

symphony_list_projects() {
    symphony_require_python || return 1

    CONFIG_FILE="${SYMPHONY_CONFIG_FILE}" python3 <<'PY'
import os
import yaml

with open(os.environ["CONFIG_FILE"], "r", encoding="utf-8") as handle:
    config = yaml.safe_load(handle) or {}

for project in config.get("projects", []):
    print(project["name"])
PY
}

symphony_project_field() {
    local project_name=$1
    local field_name=$2
    symphony_require_python || return 1

    CONFIG_FILE="${SYMPHONY_CONFIG_FILE}" PROJECT_NAME="${project_name}" FIELD_NAME="${field_name}" python3 <<'PY'
import os
import sys
import yaml

with open(os.environ["CONFIG_FILE"], "r", encoding="utf-8") as handle:
    config = yaml.safe_load(handle) or {}

project_name = os.environ["PROJECT_NAME"]
field_name = os.environ["FIELD_NAME"]

for project in config.get("projects", []):
    if project.get("name") == project_name:
        value = project.get(field_name, "")
        if value is None:
            value = ""
        print(value)
        raise SystemExit(0)

raise SystemExit(1)
PY
}

symphony_project_port() {
    local project_name=$1
    symphony_require_python || return 1

    CONFIG_FILE="${SYMPHONY_CONFIG_FILE}" PROJECT_NAME="${project_name}" python3 <<'PY'
import os
import sys
import yaml

with open(os.environ["CONFIG_FILE"], "r", encoding="utf-8") as handle:
    config = yaml.safe_load(handle) or {}

project_name = os.environ["PROJECT_NAME"]
base_port = config.get("base_port", 4001)

for index, project in enumerate(config.get("projects", [])):
    if project.get("name") == project_name:
        print(base_port + index)
        raise SystemExit(0)

raise SystemExit(1)
PY
}
