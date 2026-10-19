#!/usr/bin/env bash
# Flags Godot 3 APIs in *.gd files, then parses them. The default parse is two Godot
# processes (src, then tests): one process that loads both reports GUT scenes as leaks.
# Usage: GODOT=/path/to/godot tools/check_gdscript.sh [--renames-only|--parse-only] [paths...]
# With no paths, scans src/ and tests/. Directories that contain .gdignore are skipped
# unless that directory (or a file inside it) was named on the command line.
set -euo pipefail
GODOT="${GODOT:-godot}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"
TABLE="$ROOT/tools/gdscript_renames.txt"

mode="all"
paths=()
for arg in "$@"; do
	case "$arg" in
		--renames-only) mode="renames" ;;
		--parse-only) mode="parse" ;;
		*) paths+=("$arg") ;;
	esac
done

if [[ "$mode" != "parse" ]]; then
	if ! printf 'a\n' | grep -qP 'a'; then
		echo "check_gdscript: this script needs grep -P" >&2
		exit 1
	fi
	groups=()
	olds=()
	patterns=()
	replacements=()
	while IFS=$'\t' read -r group old pattern replacement || [[ -n "${group:-}" ]]; do
		[[ -z "${group:-}" || "$group" == \#* ]] && continue
		groups+=("$group")
		olds+=("$old")
		patterns+=("$pattern")
		replacements+=("$replacement")
	done < "$TABLE"

	shopt -s nullglob
	files=()
	failed=0
	collect() {
		local path="$1"
		local explicit="$2"
		if [[ ! -e "$path" ]]; then
			echo "check_gdscript: not found: $path" >&2
			failed=1
			return
		fi
		if [[ -f "$path" ]]; then
			[[ "$path" == *.gd ]] && files+=("$path")
			return
		fi
		local base
		base="$(basename "$path")"
		if [[ "$explicit" == "0" && ( "$base" == "addons" || -f "$path/.gdignore" ) ]]; then
			return
		fi
		local f
		for f in "$path"/*.gd; do
			files+=("$f")
		done
		local d
		for d in "$path"/*/; do
			[[ -d "$d" ]] || continue
			collect "${d%/}" 0
		done
	}
	if [[ ${#paths[@]} -eq 0 ]]; then
		collect "$ROOT/src" 1
		collect "$ROOT/tests" 1
	else
		for p in "${paths[@]}"; do
			collect "$p" 1
		done
	fi
	if [[ "$failed" -ne 0 ]]; then
		exit 1
	fi

	found=0
	if [[ ${#files[@]} -gt 0 ]]; then
		# One grep per rule, not per line: a process per line makes the scan take minutes.
		declare -A seen
		IFS=$'\n' readarray -t files < <(printf '%s\n' "${files[@]}" | sort)
		for i in "${!groups[@]}"; do
			g="${groups[$i]}"
			while IFS= read -r hit || [[ -n "${hit:-}" ]]; do
				[[ -z "${hit:-}" ]] && continue
				file="${hit%%:*}"
				rest="${hit#*:}"
				line="${rest%%:*}"
				text="${rest#*:}"
				[[ "$text" =~ ^[[:space:]]*# ]] && continue
				if [[ "$g" != "-" ]]; then
					key="$file:$line:$g"
					[[ -n "${seen[$key]+x}" ]] && continue
					seen["$key"]=1
				fi
				rel="${file#"$ROOT"/}"
				printf "%s:%s: Godot 3 API '%s' -> %s\n" "$rel" "$line" "${olds[$i]}" "${replacements[$i]}"
				found=1
			done < <(grep -nHP -- "${patterns[$i]}" "${files[@]}" || true)
		done
	fi
	if [[ "$found" -ne 0 ]]; then
		exit 1
	fi
fi

if [[ "$mode" == "renames" ]]; then
	exit 0
fi

if [[ "$mode" == "all" ]]; then
	mkdir -p .godot
	"$GODOT" --headless --path . --import > .godot/import.log 2>&1 || true
fi
# One Godot process for src and another for tests. Loading both in one process makes Godot
# report GUT scenes as leaks at exit, which hides a real parse error in the log.
parse_paths() {
	"$GODOT" --headless --path . -s tools/check_gdscript.gd -- --parse-only "$@"
}
if [[ ${#paths[@]} -eq 0 ]]; then
	set +e
	parse_paths src
	src_code=$?
	parse_paths tests
	tests_code=$?
	set -e
	if [[ "$src_code" -ne 0 ]]; then
		exit "$src_code"
	fi
	exit "$tests_code"
fi
parse_paths ${paths[@]+"${paths[@]}"}
