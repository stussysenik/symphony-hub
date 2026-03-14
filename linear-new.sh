#!/usr/bin/env bash
# linear-new.sh - Open a pre-filled Linear issue composer.

set -euo pipefail

print_usage() {
    cat <<'EOF'
Usage:
  ./linear-new.sh [options]

Options:
  --team <KEY>          Team key, e.g. CRE
  --title <TEXT>        Issue title
  --description <TEXT>  Issue description
  --status <TEXT>       Initial status, e.g. Triage or Todo
  --labels <CSV>        Comma-separated labels
  --project <TEXT>      Project name
  --template <UUID>     Template UUID
  --print               Print URL instead of opening it
  --help                Show this help text

Examples:
  ./linear-new.sh --team CRE --status Triage --labels feature,frontend
  ./linear-new.sh --team CRE --status Todo --title "Add dark mode toggle"
EOF
}

TEAM=""
TITLE=""
DESCRIPTION=""
STATUS=""
LABELS=""
PROJECT=""
TEMPLATE=""
PRINT_ONLY="false"

while [ $# -gt 0 ]; do
    case "$1" in
        --team)
            TEAM="${2:-}"
            shift 2
            ;;
        --title)
            TITLE="${2:-}"
            shift 2
            ;;
        --description)
            DESCRIPTION="${2:-}"
            shift 2
            ;;
        --status)
            STATUS="${2:-}"
            shift 2
            ;;
        --labels)
            LABELS="${2:-}"
            shift 2
            ;;
        --project)
            PROJECT="${2:-}"
            shift 2
            ;;
        --template)
            TEMPLATE="${2:-}"
            shift 2
            ;;
        --print)
            PRINT_ONLY="true"
            shift
            ;;
        --help|-h)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_usage
            exit 1
            ;;
    esac
done

export TEAM TITLE DESCRIPTION STATUS LABELS PROJECT TEMPLATE

URL=$(python3 <<'PY'
import os
from urllib.parse import urlencode

team = os.environ.get("TEAM", "").strip()
params = {}

for env_key, query_key in [
    ("TITLE", "title"),
    ("DESCRIPTION", "description"),
    ("STATUS", "status"),
    ("LABELS", "labels"),
    ("PROJECT", "project"),
    ("TEMPLATE", "template"),
]:
    value = os.environ.get(env_key, "").strip()
    if value:
        params[query_key] = value

base = "https://linear.new"
if team:
    base = f"https://linear.app/team/{team}/new"

query = urlencode(params)
print(f"{base}?{query}" if query else base)
PY
)

if [ "$PRINT_ONLY" = "true" ]; then
    printf '%s\n' "$URL"
    exit 0
fi

if command -v open >/dev/null 2>&1; then
    open "$URL"
elif command -v xdg-open >/dev/null 2>&1; then
    xdg-open "$URL" >/dev/null 2>&1 &
else
    printf '%s\n' "$URL"
fi
