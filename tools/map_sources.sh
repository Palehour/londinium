#!/usr/bin/env bash
# Rebuilds the GeoJSON layers of data/maps/sources/<id>/ from its committed raw downloads (sources.json); then run
# tools/map_import.sh. Usage:
#   GODOT=/path/to/godot tools/map_sources.sh <map_id>|all [--check|--compare]   (tools/map_sources/README.md)
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
mkdir -p .godot
"$GODOT" --headless --path . --import > .godot/import.log 2>&1 || true
"$GODOT" --headless --path . -s tools/map_sources/map_sources.gd -- "$@"
