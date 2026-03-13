#!/usr/bin/env bash
# Symphony Multi-Instance Launcher
# Manages Symphony instances for multiple projects
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_FILE="${SCRIPT_DIR}/projects.yml"
ENV_FILE="${SCRIPT_DIR}/.env.local"
PID_DIR="${SCRIPT_DIR}/pids"
LOG_DIR="${SCRIPT_DIR}/logs"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Ensure directories exist
mkdir -p "${PID_DIR}" "${LOG_DIR}"

# Load environment variables
if [ -f "${ENV_FILE}" ]; then
    set -a
    source "${ENV_FILE}"
    set +a
else
    echo -e "${RED}Error: ${ENV_FILE} not found${NC}"
    exit 1
fi

# Check if Symphony binary exists
SYMPHONY_BIN=$(python3 -c "import yaml; print(yaml.safe_load(open('${CONFIG_FILE}'))['symphony_bin'])")
if [ ! -f "${SYMPHONY_BIN}" ]; then
    echo -e "${RED}Error: Symphony binary not found at ${SYMPHONY_BIN}${NC}"
    exit 1
fi

# Function to get projects from config
get_projects() {
    CONFIG_FILE="${CONFIG_FILE}" python3 << 'EOF'
import yaml
import sys
import os

config_file = os.environ.get('CONFIG_FILE')
with open(config_file, 'r') as f:
    config = yaml.safe_load(f)

for project in config['projects']:
    print(project['name'])
EOF
}

# Function to get project port
get_project_port() {
    local project_name=$1
    CONFIG_FILE="${CONFIG_FILE}" python3 << EOF
import yaml
import os

config_file = os.environ.get('CONFIG_FILE')
with open(config_file, 'r') as f:
    config = yaml.safe_load(f)

base_port = config.get('base_port', 4001)
projects = config['projects']

for i, project in enumerate(projects):
    if project['name'] == '${project_name}':
        print(base_port + i)
        break
EOF
}

# Function to start a single Symphony instance
start_project() {
    local project_name=$1
    local port=$(get_project_port "${project_name}")
    local workflow_file="${SCRIPT_DIR}/workflows/${project_name}.WORKFLOW.md"
    local pid_file="${PID_DIR}/${project_name}.pid"
    local log_file="${LOG_DIR}/${project_name}.log"

    # Check if workflow exists
    if [ ! -f "${workflow_file}" ]; then
        echo -e "${RED}  Error: Workflow file not found: ${workflow_file}${NC}"
        return 1
    fi

    # Check if already running
    if [ -f "${pid_file}" ]; then
        local pid=$(cat "${pid_file}")
        if ps -p "${pid}" > /dev/null 2>&1; then
            echo -e "${YELLOW}  Already running (PID ${pid}, port ${port})${NC}"
            return 0
        else
            # Stale PID file
            rm -f "${pid_file}"
        fi
    fi

    echo -e "${BLUE}[symphony]${NC} Starting ${project_name} on port ${port}..."

    # Start Symphony with workflow file
    # Syntax: symphony [--logs-root <path>] [--port <port>] [path-to-WORKFLOW.md]
    LINEAR_API_KEY="${LINEAR_API_KEY}" \
    nohup "${SYMPHONY_BIN}" \
        --i-understand-that-this-will-be-running-without-the-usual-guardrails \
        --logs-root "${LOG_DIR}" \
        --port "${port}" \
        "${workflow_file}" \
        > "${log_file}" 2>&1 &

    local pid=$!
    echo "${pid}" > "${pid_file}"

    # Wait a moment and check if it's still running
    sleep 2
    if ps -p "${pid}" > /dev/null 2>&1; then
        echo -e "${GREEN}  ✅ Started ${project_name} (PID ${pid}, port ${port})${NC}"
        echo -e "     Dashboard: ${BLUE}http://localhost:${port}${NC}"
    else
        echo -e "${RED}  ❌ Failed to start ${project_name}${NC}"
        echo -e "     Check logs: tail -f ${log_file}"
        rm -f "${pid_file}"
        return 1
    fi
}

# Function to stop a single Symphony instance
stop_project() {
    local project_name=$1
    local pid_file="${PID_DIR}/${project_name}.pid"

    if [ ! -f "${pid_file}" ]; then
        echo -e "${YELLOW}  ${project_name}: not running${NC}"
        return 0
    fi

    local pid=$(cat "${pid_file}")
    if ps -p "${pid}" > /dev/null 2>&1; then
        echo -e "${BLUE}[symphony]${NC} Stopping ${project_name} (PID ${pid})..."
        kill "${pid}"
        sleep 2

        # Force kill if still running
        if ps -p "${pid}" > /dev/null 2>&1; then
            echo -e "${YELLOW}  Force killing ${project_name}...${NC}"
            kill -9 "${pid}"
        fi

        rm -f "${pid_file}"
        echo -e "${GREEN}  ✅ Stopped ${project_name}${NC}"
    else
        echo -e "${YELLOW}  ${project_name}: not running (stale PID)${NC}"
        rm -f "${pid_file}"
    fi
}

# Function to check status of a single instance
status_project() {
    local project_name=$1
    local pid_file="${PID_DIR}/${project_name}.pid"
    local port=$(get_project_port "${project_name}")

    if [ ! -f "${pid_file}" ]; then
        echo -e "  ${project_name}: ${RED}STOPPED${NC}"
        return 1
    fi

    local pid=$(cat "${pid_file}")
    if ps -p "${pid}" > /dev/null 2>&1; then
        echo -e "  ${project_name}: ${GREEN}RUNNING${NC} (PID ${pid}, port ${port})"
        echo -e "    Dashboard: ${BLUE}http://localhost:${port}${NC}"
    else
        echo -e "  ${project_name}: ${RED}STOPPED${NC} (stale PID)"
        rm -f "${pid_file}"
        return 1
    fi
}

# Function to show logs for a project
logs_project() {
    local project_name=$1
    local log_file="${LOG_DIR}/${project_name}.log"

    if [ ! -f "${log_file}" ]; then
        echo -e "${RED}No logs found for ${project_name}${NC}"
        return 1
    fi

    echo -e "${BLUE}=== Logs for ${project_name} ===${NC}"
    echo -e "${YELLOW}Log file: ${log_file}${NC}"
    echo
    tail -f "${log_file}"
}

# Command handlers
cmd_start() {
    if [ $# -eq 0 ]; then
        # Start all projects
        echo -e "${BLUE}[symphony]${NC} Starting all Symphony instances..."
        echo
        for project in $(get_projects); do
            start_project "${project}"
        done
        echo
        echo -e "${GREEN}All instances started!${NC}"
        echo
        cmd_status
    else
        # Start specific project
        start_project "$1"
    fi
}

cmd_stop() {
    if [ $# -eq 0 ]; then
        # Stop all projects
        echo -e "${BLUE}[symphony]${NC} Stopping all Symphony instances..."
        echo
        for project in $(get_projects); do
            stop_project "${project}"
        done
        echo
        echo -e "${GREEN}All instances stopped!${NC}"
    else
        # Stop specific project
        stop_project "$1"
    fi
}

cmd_restart() {
    if [ $# -eq 0 ]; then
        # Restart all
        cmd_stop
        sleep 2
        cmd_start
    else
        # Restart specific project
        stop_project "$1"
        sleep 2
        start_project "$1"
    fi
}

cmd_status() {
    echo -e "${BLUE}[symphony]${NC} Status:"
    echo
    for project in $(get_projects); do
        status_project "${project}"
    done
}

cmd_logs() {
    if [ $# -eq 0 ]; then
        echo -e "${RED}Usage: $0 logs <project-name>${NC}"
        echo -e "\nAvailable projects:"
        for project in $(get_projects); do
            echo "  - ${project}"
        done
        exit 1
    fi

    logs_project "$1"
}

cmd_help() {
    cat << 'HELP'
Symphony Multi-Instance Launcher

Usage: ./launch.sh <command> [project-name]

Commands:
  start [project]    Start Symphony instance(s)
  stop [project]     Stop Symphony instance(s)
  restart [project]  Restart Symphony instance(s)
  status             Show status of all instances
  logs <project>     Tail logs for a project
  help               Show this help message

Examples:
  ./launch.sh start              # Start all projects
  ./launch.sh start v0-ipod      # Start only v0-ipod
  ./launch.sh stop               # Stop all projects
  ./launch.sh restart            # Restart all projects
  ./launch.sh status             # Show status of all instances
  ./launch.sh logs v0-ipod       # Tail logs for v0-ipod

Projects:
HELP

    for project in $(get_projects); do
        local port=$(get_project_port "${project}")
        echo "  - ${project} (port ${port})"
    done
}

# Main command router
main() {
    local command="${1:-help}"
    shift || true

    case "${command}" in
        start)
            cmd_start "$@"
            ;;
        stop)
            cmd_stop "$@"
            ;;
        restart)
            cmd_restart "$@"
            ;;
        status)
            cmd_status "$@"
            ;;
        logs)
            cmd_logs "$@"
            ;;
        help|--help|-h)
            cmd_help
            ;;
        *)
            echo -e "${RED}Unknown command: ${command}${NC}"
            echo
            cmd_help
            exit 1
            ;;
    esac
}

main "$@"
