#!/usr/bin/env bash
# Runs the long scenario tests (tests/scenarios/long/long_test_*.gd): 20 seeds of 70-minute games, too slow
# for CI. Their files do not start with test_, so tools/run_tests and CI never pick them up.
# Usage: GODOT=/path/to/godot tools/run_long_tests.sh [extra GUT args]
set -euo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.."
mkdir -p .godot
# Builds the .godot/ cache and class_name list. Log kept in .godot/import.log (check it for new warnings).
"$GODOT" --headless --path . --import 2>&1 | tee .godot/import.log || true
# -gconfig= skips .gutconfig.json, whose dirs and prefix are the ones of the short suite.
"$GODOT" --headless --path . -s addons/gut/gut_cmdln.gd -gexit -gconfig= \
	-gdir=res://tests/scenarios/long -gprefix=long_test_ "$@"
