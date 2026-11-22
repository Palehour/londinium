#!/usr/bin/env bash
# Runs the verification CLI headless and keeps its stdout+stderr as log.txt in the evidence folder.
# Usage: GODOT=/path/to/godot tools/verificar.sh [verificar.gd options]
# Exit code: the CLI's (0 ok, 1 failed expectation, 2 usage/data error); 2 also if the log cannot be saved.
# Does not run --import: tools/run_tests.sh builds the .godot cache.
set -uo pipefail
GODOT="${GODOT:-godot}"
cd "$(dirname "$0")/.." || { echo "verificar: cannot enter the repo root" >&2; exit 2; }

if ! command -v "$GODOT" >/dev/null 2>&1; then
	echo "verificar: Godot not found ('$GODOT'); set GODOT to the 4.7.2 console binary" >&2
	exit 2
fi

# Per-run temp log, so two worktrees never share a file.
LOG="$(mktemp "${TMPDIR:-/tmp}/verificar.XXXXXX")" || { echo "verificar: cannot create temp log" >&2; exit 2; }
trap 'rm -f "$LOG"' EXIT

"$GODOT" --headless --path . -s tools/verificar.gd -- "$@" 2>&1 | tee "$LOG"
# One assignment: any later command would reset PIPESTATUS.
PIPE_STATUS=("${PIPESTATUS[@]}")
STATUS="${PIPE_STATUS[0]}"
TEE_STATUS="${PIPE_STATUS[1]}"

fail() { echo "verificar: $1" >&2; exit 2; }

# Unexpected native status (crash, signal): pass it through untouched.
case "$STATUS" in 0|1|2) ;; *) exit "$STATUS" ;; esac
[ "$TEE_STATUS" -eq 0 ] || fail "could not capture the log"

# Only the FIRST marker counts: the CLI prints it before running anything, so anything later
# (game output, push_error text) cannot redirect the copy. CR is stripped for Windows-style output.
MARKER="$(grep -a -m1 '^VERIFICAR_SALIDA=' "$LOG" | tr -d '\r' || true)"
OUT="${MARKER#VERIFICAR_SALIDA=}"
if [ -z "$OUT" ]; then
	# No marker is legitimate only for a sole --help (exit 0) or a CLI error before it chose a folder (exit 2).
	if [ "$STATUS" -eq 0 ] && [ "$#" -eq 1 ] && [ "$1" = "--help" ]; then exit 0; fi
	[ "$STATUS" -eq 2 ] && exit 2
	fail "no output directory marker found, log.txt not saved"
fi
case "$OUT" in /*) ;; *) fail "output directory '$OUT' is not absolute, log.txt not saved" ;; esac
[ -d "$OUT" ] || fail "invalid output directory '$OUT', log.txt not saved"
# An existing log.txt must be a plain file: cp would follow a symlink or drop the log inside a directory.
if [ -L "$OUT/log.txt" ] || { [ -e "$OUT/log.txt" ] && [ ! -f "$OUT/log.txt" ]; }; then
	fail "'$OUT/log.txt' is not a regular file, log.txt not saved"
fi
cp "$LOG" "$OUT/log.txt" || fail "could not write $OUT/log.txt"
# Keep the CLI's own status: 0 ok, 1 failed expectation, 2 data error (log kept for all three).
exit "$STATUS"
