#!/usr/bin/env bash
# Every .gd in the Git index needs its .gd.uid companion in the index too.
# Godot generates the .uid on import; if it is not committed, the next import
# invents a new one and the script's identity changes between machines.
# Checks the index only (honours GIT_INDEX_FILE), never the working tree.
# Skips addons/ and scripts under any directory that has an indexed .gdignore.
# Usage: bash tools/check_script_uids.sh
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

list="$(mktemp)"
trap 'rm -f "$list"' EXIT
# Write to a file first so a git failure aborts the script (set -e) instead of
# being hidden inside a process substitution.
git ls-files -z --cached > "$list"

declare -A indexed=()
declare -A ignored_dirs=()
gd_files=()
while IFS= read -r -d '' path; do
	indexed["$path"]=1
	case "$path" in
		*.gd) gd_files+=("$path") ;;
		.gdignore) ignored_dirs["."]=1 ;;
		*/.gdignore) ignored_dirs["${path%/.gdignore}"]=1 ;;
	esac
done < "$list"

is_ignored() {
	local path="$1"
	[[ "$path" == addons/* ]] && return 0
	[[ -n "${ignored_dirs[.]+x}" ]] && return 0
	local dir="${path%/*}"
	while [[ "$dir" != "$path" && "$dir" == */* ]]; do
		[[ -n "${ignored_dirs[$dir]+x}" ]] && return 0
		dir="${dir%/*}"
	done
	# Top-level directory (no slash left in dir) is checked here.
	[[ "$path" == */* && -n "${ignored_dirs[$dir]+x}" ]] && return 0
	return 1
}

checked=0
missing=0
for f in ${gd_files[@]+"${gd_files[@]}"}; do
	is_ignored "$f" && continue
	checked=$((checked + 1))
	if [[ -z "${indexed[$f.uid]+x}" ]]; then
		printf 'check_script_uids: missing %s.uid in the Git index\n' "$f" >&2
		missing=$((missing + 1))
	fi
done

if [[ "$missing" -ne 0 ]]; then
	echo "check_script_uids: $missing script(s) without .uid. Generate them with" \
		"'godot --headless --path . --import', then stage and commit each companion .gd.uid." >&2
	exit 1
fi
echo "check_script_uids: ok ($checked scripts checked)"
