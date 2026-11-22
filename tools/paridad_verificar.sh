#!/usr/bin/env bash
# Parity check (#389): tools/verificar.sh and tools/verificar.ps1 (run with pwsh) must leave the same evidence.
# Usage: GODOT=/path/to/godot tools/paridad_verificar.sh [work dir]   (default: a new temp dir)
# Needs bash and pwsh in PATH; Godot must be imported already. Exit 0 = parity, 1 = a difference, 2 = setup error.
set -uo pipefail
cd "$(dirname "$0")/.." || { echo "paridad: cannot enter the repo root" >&2; exit 2; }
command -v pwsh >/dev/null 2>&1 || { echo "paridad: pwsh not found in PATH" >&2; exit 2; }

WORK="${1:-$(mktemp -d "${TMPDIR:-/tmp}/paridad.XXXXXX")}" || exit 2
WORK="$(realpath -m "$WORK")" || exit 2
SH_OUT="$WORK/ci-sh"
PS_OUT="$WORK/ci-ps1"
ARGS=(--escenario small_rich --modo sim)
FAILED=0
fail() { echo "paridad: FAIL: $1" >&2; FAILED=1; }

# Runs one wrapper, keeps its console output as $2.console and its exit code in $2.exit.
run_wrapper() { # kind label args...
	local kind="$1" label="$2"
	shift 2
	if [ "$kind" = sh ]; then bash tools/verificar.sh "$@" >"$WORK/$label.console" 2>&1
	else pwsh -NoProfile -File tools/verificar.ps1 "$@" >"$WORK/$label.console" 2>&1; fi
	echo $? >"$WORK/$label.exit"
}
expect_exit() { # label want
	local status
	status="$(cat "$WORK/$1.exit")"
	if [ "$status" != "$2" ]; then
		fail "$1 exit $status, expected $2"
		head -20 "$WORK/$1.console" >&2
	fi
}
# CRLF to LF and the run's own absolute folder to a placeholder: the only differences allowed in text evidence.
lf() { sed $'s/\r$//' "$1"; }
normalize() {
	local path
	path="$(printf '%s' "$2" | sed 's/[][\\.^$*|]/\\&/g')"
	lf "$1" | sed "s|$path|<SALIDA>|g"
}

mkdir -p "$WORK" || exit 2
run_wrapper sh sh "${ARGS[@]}" --salida "$SH_OUT"
run_wrapper ps1 ps1 "${ARGS[@]}" --salida "$PS_OUT"
expect_exit sh 0
expect_exit ps1 0

for f in estado.json serie.csv resumen.json log.txt; do
	for d in "$SH_OUT" "$PS_OUT"; do [ -f "$d/$f" ] || fail "$d/$f is missing"; done
done
if [ "$FAILED" -eq 0 ]; then
	for f in estado.json serie.csv resumen.json; do
		cmp -s "$SH_OUT/$f" "$PS_OUT/$f" || { fail "$f differs byte by byte"; diff "$SH_OUT/$f" "$PS_OUT/$f" | head -20 >&2; }
	done
	diff <(normalize "$SH_OUT/log.txt" "$SH_OUT") <(normalize "$PS_OUT/log.txt" "$PS_OUT") >"$WORK/log.diff" \
		|| { fail "log.txt differs after normalizing CRLF and the folder"; head -20 "$WORK/log.diff" >&2; }
	for l in sh ps1; do
		d="$SH_OUT"; [ "$l" = ps1 ] && d="$PS_OUT"
		marker="$(lf "$WORK/$l.console" | grep -a '^VERIFICAR_SALIDA=')"
		[ "$marker" = "VERIFICAR_SALIDA=$d" ] || fail "$l must print exactly one marker pointing to --salida"
	done
	diff <(normalize "$WORK/sh.console" "$SH_OUT") <(normalize "$WORK/ps1.console" "$PS_OUT") >"$WORK/console.diff" \
		|| { fail "console output differs after normalizing CRLF and the folder"; head -20 "$WORK/console.diff" >&2; }
fi

# --help: exit 0, no evidence folder. Usage error: exit 2.
default_folders() {
	if [ -d build/verificacion ]; then find build/verificacion -maxdepth 1 -type d | sort; fi
}
for k in sh ps1; do
	before="$(default_folders)" || exit 2
	run_wrapper "$k" "help-$k" --help
	expect_exit "help-$k" 0
	after="$(default_folders)" || exit 2
	[ "$before" = "$after" ] || fail "$k --help created an evidence folder"
	! grep -aq '^VERIFICAR_SALIDA=' "$WORK/help-$k.console" || fail "$k --help reported an evidence folder"
	run_wrapper "$k" "uso-$k"
	expect_exit "uso-$k" 2
done
diff -u <(lf "$WORK/help-sh.console") <(lf "$WORK/help-ps1.console") || fail "--help output differs"
diff -u <(lf "$WORK/uso-sh.console") <(lf "$WORK/uso-ps1.console") || fail "usage error output differs"

if [ "$FAILED" -eq 0 ]; then echo "paridad: OK (sh and ps1: small_rich=0, --help=0, no args=2; evidence in $WORK)"; exit 0; fi
echo "paridad: differences found; evidence in $WORK" >&2
exit 1
