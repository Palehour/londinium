#!/usr/bin/env bash
# Per-minute balance CSV for the scripted scenarios. Usage:
#   GODOT=/path/to/godot tools/balance_report.sh [--scenario <id>|all] [--out <dir>]
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
mkdir -p .godot
"$GODOT" --headless --path . --import > .godot/import.log 2>&1 || true
"$GODOT" --headless --path . -s tools/balance_report.gd -- "$@"
