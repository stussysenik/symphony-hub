#!/usr/bin/env bash
# checkpoint.sh - Save a resumable local snapshot of hub/engine/runtime state.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "${SCRIPT_DIR}/config.sh"

ENV_FILE="${SCRIPT_DIR}/.env.local"
if [ -f "${ENV_FILE}" ]; then
    set -a
    # shellcheck disable=SC1090
    source "${ENV_FILE}"
    set +a
fi

CHECKPOINT_ROOT="${SCRIPT_DIR}/checkpoints"
TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
RAW_LABEL="${*:-}"
SAFE_LABEL=""

if [ -n "${RAW_LABEL}" ]; then
    SAFE_LABEL="$(printf '%s' "${RAW_LABEL}" | tr '[:upper:]' '[:lower:]' | tr -cs 'a-z0-9._-' '-')"
    SAFE_LABEL="${SAFE_LABEL#-}"
    SAFE_LABEL="${SAFE_LABEL%-}"
fi

CHECKPOINT_DIR="${CHECKPOINT_ROOT}/${TIMESTAMP}${SAFE_LABEL:+-${SAFE_LABEL}}"
LATEST_LINK="${CHECKPOINT_ROOT}/latest"

ENGINE_ROOT="$(symphony_config_get "engine.repo_root")"
ENGINE_FORK_URL="$(symphony_config_get "engine.fork_url")"
ENGINE_UPSTREAM_URL="$(symphony_config_get "engine.upstream_url")"
ENGINE_EXPECTED_BRANCH="$(symphony_config_get "engine.expected_branch")"
WORKSPACE_ROOT="$(symphony_config_get "workspace_root")"
LOGS_ROOT="$(symphony_config_get "logs_root")"
WORKFLOWS_DIR="$(symphony_config_get "workflows_dir")"

mkdir -p "${CHECKPOINT_DIR}/hub" \
         "${CHECKPOINT_DIR}/engine" \
         "${CHECKPOINT_DIR}/runtime/log-tails" \
         "${CHECKPOINT_DIR}/linear" \
         "${CHECKPOINT_DIR}/config/workflows"

cp "${SCRIPT_DIR}/projects.yml" "${CHECKPOINT_DIR}/config/projects.yml"
cp "${SCRIPT_DIR}/WORKFLOW.template.md" "${CHECKPOINT_DIR}/config/WORKFLOW.template.md"
cp "${SCRIPT_DIR}/generate-workflows.sh" "${CHECKPOINT_DIR}/config/generate-workflows.sh"
cp "${WORKFLOWS_DIR}"/*.WORKFLOW.md "${CHECKPOINT_DIR}/config/workflows/" 2>/dev/null || true

git -C "${SCRIPT_DIR}" status --short --branch > "${CHECKPOINT_DIR}/hub/git-status.txt" || true
git -C "${SCRIPT_DIR}" diff --stat > "${CHECKPOINT_DIR}/hub/git-diff-stat.txt" || true
git -C "${SCRIPT_DIR}" remote -v > "${CHECKPOINT_DIR}/hub/remotes.txt" || true
git -C "${SCRIPT_DIR}" rev-parse HEAD > "${CHECKPOINT_DIR}/hub/head.txt" || true

if [ -n "${ENGINE_ROOT}" ] && [ -d "${ENGINE_ROOT}" ]; then
    printf '%s\n' "${ENGINE_FORK_URL}" > "${CHECKPOINT_DIR}/engine/fork-url.txt"
    printf '%s\n' "${ENGINE_UPSTREAM_URL}" > "${CHECKPOINT_DIR}/engine/upstream-url.txt"
    printf '%s\n' "${ENGINE_EXPECTED_BRANCH}" > "${CHECKPOINT_DIR}/engine/expected-branch.txt"
    printf '%s\n' "${ENGINE_ROOT}" > "${CHECKPOINT_DIR}/engine/path.txt"

    if [ -d "${ENGINE_ROOT}/.git" ]; then
        git -C "${ENGINE_ROOT}" status --short --branch > "${CHECKPOINT_DIR}/engine/git-status.txt" || true
        git -C "${ENGINE_ROOT}" remote -v > "${CHECKPOINT_DIR}/engine/remotes.txt" || true
        git -C "${ENGINE_ROOT}" rev-parse HEAD > "${CHECKPOINT_DIR}/engine/head.txt" || true
    else
        printf 'Configured engine repo is not a git checkout: %s\n' "${ENGINE_ROOT}" > "${CHECKPOINT_DIR}/engine/notes.txt"
    fi
else
    {
        printf 'Engine repo unavailable.\n'
        printf 'Configured path: %s\n' "${ENGINE_ROOT:-<unset>}"
        printf 'Fork URL: %s\n' "${ENGINE_FORK_URL:-<unset>}"
        printf 'Upstream URL: %s\n' "${ENGINE_UPSTREAM_URL:-<unset>}"
    } > "${CHECKPOINT_DIR}/engine/notes.txt"
fi

"${SCRIPT_DIR}/launch.sh" status > "${CHECKPOINT_DIR}/runtime/launch-status.txt" 2>&1 || true
find "${WORKSPACE_ROOT}" -maxdepth 2 -mindepth 1 -type d | sort > "${CHECKPOINT_DIR}/runtime/workspaces.txt" 2>/dev/null || true

for project in $(symphony_list_projects); do
    if [ -f "${LOGS_ROOT}/${project}.log" ]; then
        tail -n 120 "${LOGS_ROOT}/${project}.log" > "${CHECKPOINT_DIR}/runtime/log-tails/${project}.log.txt" || true
    fi
done

if [ -x "${SCRIPT_DIR}/linear-audit.sh" ] && [ -n "${LINEAR_API_KEY:-}" ]; then
    if "${SCRIPT_DIR}/linear-audit.sh" > "${CHECKPOINT_DIR}/linear/audit.txt" 2> "${CHECKPOINT_DIR}/linear/audit.stderr.txt"; then
        :
    else
        printf 'Linear audit failed. See audit.stderr.txt.\n' >> "${CHECKPOINT_DIR}/linear/audit.txt"
    fi
else
    printf 'Linear audit skipped (missing LINEAR_API_KEY or script unavailable).\n' > "${CHECKPOINT_DIR}/linear/audit.txt"
fi

HUB_HEAD="$(git -C "${SCRIPT_DIR}" rev-parse --short HEAD 2>/dev/null || echo unknown)"
HUB_DIRTY_COUNT="$(git -C "${SCRIPT_DIR}" status --short 2>/dev/null | wc -l | tr -d ' ')"

PROJECT_SUMMARY_LINES=()
for project in $(symphony_list_projects); do
    status="STOPPED"
    port="$(symphony_project_port "${project}")"
    workspace_strategy="$(symphony_project_field "${project}" "workspace_strategy" || true)"
    repo_root="$(symphony_project_field "${project}" "repo_root" || true)"
    project_workspace_root="${WORKSPACE_ROOT}/${project}"
    workspace_count=0
    latest_workspace="none"

    if [ -f "${SCRIPT_DIR}/pids/${project}.pid" ]; then
        pid="$(cat "${SCRIPT_DIR}/pids/${project}.pid")"
        if ps -p "${pid}" >/dev/null 2>&1; then
            status="RUNNING"
        fi
    fi

    if [ -d "${project_workspace_root}" ]; then
        workspace_count="$(find "${project_workspace_root}" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')"
        latest_workspace="$(ls -td "${project_workspace_root}"/* 2>/dev/null | head -1 || true)"
        if [ -z "${latest_workspace}" ]; then
            latest_workspace="none"
        fi
    fi

    PROJECT_SUMMARY_LINES+=("${project}|${status}|${port}|${workspace_strategy}|${repo_root}|${workspace_count}|${latest_workspace}")
done

CHECKPOINT_NAME="$(basename "${CHECKPOINT_DIR}")" \
ENGINE_ROOT="${ENGINE_ROOT}" \
ENGINE_FORK_URL="${ENGINE_FORK_URL}" \
ENGINE_UPSTREAM_URL="${ENGINE_UPSTREAM_URL}" \
ENGINE_EXPECTED_BRANCH="${ENGINE_EXPECTED_BRANCH}" \
WORKSPACE_ROOT="${WORKSPACE_ROOT}" \
LOGS_ROOT="${LOGS_ROOT}" \
WORKFLOWS_DIR="${WORKFLOWS_DIR}" \
PROJECT_SUMMARY="$(printf '%s\n' "${PROJECT_SUMMARY_LINES[@]}")" \
python3 <<'PY' > "${CHECKPOINT_DIR}/metadata.json"
import json
import os

projects = []
for line in os.environ.get("PROJECT_SUMMARY", "").splitlines():
    if not line:
        continue
    name, status, port, strategy, repo_root, workspace_count, latest_workspace = line.split("|", 6)
    projects.append({
        "name": name,
        "status": status,
        "port": int(port),
        "workspaceStrategy": strategy,
        "repoRoot": repo_root,
        "workspaceCount": int(workspace_count),
        "latestWorkspace": latest_workspace,
    })

print(json.dumps({
    "checkpoint": os.environ["CHECKPOINT_NAME"],
    "engine": {
        "repoRoot": os.environ.get("ENGINE_ROOT", ""),
        "forkUrl": os.environ.get("ENGINE_FORK_URL", ""),
        "upstreamUrl": os.environ.get("ENGINE_UPSTREAM_URL", ""),
        "expectedBranch": os.environ.get("ENGINE_EXPECTED_BRANCH", ""),
    },
    "runtime": {
        "workspaceRoot": os.environ.get("WORKSPACE_ROOT", ""),
        "logsRoot": os.environ.get("LOGS_ROOT", ""),
        "workflowsDir": os.environ.get("WORKFLOWS_DIR", ""),
        "projects": projects,
    },
}, indent=2))
PY

cat > "${CHECKPOINT_DIR}/SUMMARY.md" <<EOF
# Symphony Checkpoint

- Created: ${TIMESTAMP}
- Label: ${RAW_LABEL:-<none>}
- Hub HEAD: ${HUB_HEAD}
- Hub dirty entries: ${HUB_DIRTY_COUNT}
- Engine repo: ${ENGINE_ROOT:-<unset>}
- Engine fork: ${ENGINE_FORK_URL:-<unset>}
- Engine upstream: ${ENGINE_UPSTREAM_URL:-<unset>}
- Engine expected branch: ${ENGINE_EXPECTED_BRANCH:-<unset>}
- Workspace root: ${WORKSPACE_ROOT}
- Logs root: ${LOGS_ROOT}
- Workflows dir: ${WORKFLOWS_DIR}

## Artifacts

- \`hub/git-status.txt\`
- \`hub/git-diff-stat.txt\`
- \`engine/git-status.txt\` or \`engine/notes.txt\`
- \`runtime/launch-status.txt\`
- \`runtime/workspaces.txt\`
- \`runtime/log-tails/\`
- \`linear/audit.txt\`
- \`metadata.json\`
- \`config/WORKFLOW.template.md\`
- \`config/workflows/\`

## Project summary

EOF

for line in "${PROJECT_SUMMARY_LINES[@]}"; do
    IFS='|' read -r project status port strategy repo_root workspace_count latest_workspace <<< "${line}"
    {
        printf -- '- `%s`: %s, port %s, strategy %s, workspaces %s, latest `%s`\n' \
            "${project}" "${status}" "${port}" "${strategy}" "${workspace_count}" "${latest_workspace}"
        printf '  repo_root: `%s`\n' "${repo_root}"
    } >> "${CHECKPOINT_DIR}/SUMMARY.md"
done

cat >> "${CHECKPOINT_DIR}/SUMMARY.md" <<EOF

## Resume order

1. Read \`linear/audit.txt\`.
2. Read \`runtime/launch-status.txt\`.
3. Inspect relevant \`runtime/log-tails/<project>.log.txt\`.
4. Inspect \`hub/git-status.txt\` and \`engine/git-status.txt\`.
5. Run \`./launch.sh sources\` for a fresh topology readout.
6. Resume the issue from its Linear workpad and active workspace.
EOF

rm -rf "${LATEST_LINK}"
ln -s "$(basename "${CHECKPOINT_DIR}")" "${LATEST_LINK}"

printf 'Checkpoint saved: %s\n' "${CHECKPOINT_DIR}"
