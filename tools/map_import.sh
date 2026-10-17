#!/usr/bin/env bash
# Rebuilds data/maps/<id>.json from its traced sources in data/maps/sources/<id>/. Usage:
#   GODOT=/path/to/godot tools/map_import.sh <map_id>|all [--check]
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
mkdir -p .godot
"$GODOT" --headless --path . --import > .godot/import.log 2>&1 || true
"$GODOT" --headless --path . -s tools/map_import/map_import.gd -- "$@"
