#!/usr/bin/env bash
# Runs the full GUT suite headless. Usage: GODOT=/path/to/godot tools/run_tests.sh [extra GUT args]
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
mkdir -p .godot
# Builds the .godot/ cache and class_name list. Log kept in .godot/import.log (check it for new warnings).
"$GODOT" --headless --path . --import 2>&1 | tee .godot/import.log || true
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gexit "$@"
