#!/usr/bin/env bash
# Runs the full GUT suite headless. Usage: GODOT=/path/to/godot tools/run_tests.sh [extra GUT args]
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
"$GODOT" --headless --path . --import >/dev/null 2>&1 || true   # builds .godot/ cache and class_name list
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gexit "$@"
