#!/bin/bash
# Smoke harness for the dep script.
#
# Runs a fixed battery of `dep` invocations against the live Portage tree and
# emits a stable, diffable snapshot to stdout. Compare across modernization
# phases with `diff -u tests/baseline.<phase>.txt <(tests/smoke.sh)`.
#
# Each command's section shows: command line, exit code, and the first N lines
# of combined stdout+stderr (colour stripped, width fixed). Long outputs are
# also summarised by line count + sha256 so we can detect changes without
# dumping thousands of lines into the diff.
#
# This script is read-only: action commands run with --pretend; overlay-clean
# is invoked on a non-existent path so it just prints what it would do.

set -u
export COLUMNS=80
export LC_ALL=C
unset PORTAGE_OVERRIDE_EPREFIX

cd "$(dirname "$0")/.." || exit 1

if [[ ! -f src/dep ]]; then
	echo "src/dep not found — run ./configure && make first" >&2
	exit 1
fi
chmod +x src/dep
DEP=./src/dep

HEAD_LINES=30  # how many lines of output to embed verbatim per command

run() {
	local label="$1"; shift
	local out rc lines hash
	out=$("$DEP" --colour=no "$@" 2>&1)
	rc=$?
	lines=$(printf '%s\n' "$out" | wc -l)
	hash=$(printf '%s' "$out" | sha256sum | cut -c1-12)
	printf '\n=== %s ===\n' "$label"
	printf '$ dep --colour=no %s\n' "$*"
	printf '[exit=%d lines=%d sha=%s]\n' "$rc" "$lines" "$hash"
	printf '%s\n' "$out" | head -n "$HEAD_LINES"
	if (( lines > HEAD_LINES )); then
		printf '... (%d more lines)\n' "$((lines - HEAD_LINES))"
	fi
}

# Pick targets that exist on this system. We want stable, common packages.
pick_one() {
	for cand in "$@"; do
		[[ -d /var/db/pkg/$cand ]] && { echo "$cand"; return; }
	done
}
pick_glob() {
	# pick first installed package matching cat/name-prefix
	local g
	for g in "$@"; do
		set +u
		local m=( /var/db/pkg/$g* )
		set -u
		[[ -d "${m[0]}" ]] && { echo "${m[0]#/var/db/pkg/}"; return; }
	done
}

PORTAGE=$(pick_glob sys-apps/portage)
BASH_PKG=$(pick_glob app-shells/bash)
PYTHON=$(pick_glob dev-lang/python-3)
GLIBC=$(pick_glob sys-libs/glibc)
VIRTUAL_EDITOR=$(pick_one virtual/editor)
VIRTUAL_LIBC=$(pick_one virtual/libc)

# A short package-name (PN) for actions that take PNAME
PN_PORTAGE=portage
PN_BASH=bash
PN_PYTHON=python

# A file path likely owned by something
OWNED_FILE=/usr/bin/bash

printf 'udept smoke harness — %s\n' "$(date -u +%FT%TZ)"
printf 'dep version: '; "$DEP" --colour=no --version | head -1
printf 'host: %s\n' "$(uname -srm)"
printf 'PORTAGE=%s BASH=%s PYTHON=%s GLIBC=%s VIRTUAL_EDITOR=%s VIRTUAL_LIBC=%s\n' \
	"$PORTAGE" "$BASH_PKG" "$PYTHON" "$GLIBC" "$VIRTUAL_EDITOR" "$VIRTUAL_LIBC"

# --- Help / metadata -----------------------------------------------------
run 'usage'   --usage
run 'version' --version
run 'help'    --help

# --- Info actions: take a PACKAGE or PNAME -------------------------------
run 'depends/portage'         -l "$PORTAGE"
run 'depends/bash'            -l "$BASH_PKG"
run 'depends/python'          -l "$PYTHON"
run 'rev-depends/portage'     -L "$PN_PORTAGE"
run 'rev-depends/bash'        -L "$PN_BASH"
run 'rev-depends/python'      -L "$PN_PYTHON"
run 'tree-depends/portage'    -t "$PORTAGE" -D 2
run 'reverse-tree/python'     -T "$PN_PYTHON" -D 2
run 'depstrings/portage'      -S "$PORTAGE"
run 'versions/python'         -e "$PN_PYTHON"
run 'keywords/python'         -k "$PN_PYTHON"
run 'info/portage'            -i "$PORTAGE"
run 'contents/portage'        -f "$PORTAGE"
run 'category/portage'        -c "$PN_PORTAGE"
run 'catpackages/sys-apps'    -C sys-apps
run 'changelog/portage'       -j "$PN_PORTAGE" 3
run 'usedesc/portage'         -u "$PORTAGE"
run 'iuse/python'             -U python
run 'size/portage'            -z "$PORTAGE"
run 'search/portage'          -g portage
run 'owners/file'             -F "$OWNED_FILE"

# --- Virtuals (currently broken — captures pre-fix behaviour) -----------
[[ "$VIRTUAL_EDITOR" ]] && run 'virtuals/editor' -R "${VIRTUAL_EDITOR%-[0-9]*}"
[[ "$VIRTUAL_LIBC" ]]   && run 'virtuals/libc'   -R "${VIRTUAL_LIBC%-[0-9]*}"
run 'provides/portage'        -r "$PORTAGE"

# --- Existence probes ----------------------------------------------------
run 'exists/portage:bash'     -x "$PORTAGE" "$PN_BASH"
run 'rev-exists/python:bash'  -X "$PN_PYTHON" "$PN_BASH"

# --- Actions, all read-only / pretend -----------------------------------
run 'pruneworld/pretend'         -wp
run 'depclean/pretend'           -dp
run 'purge/pretend'              -Pp
run 'filter-etc-portage'         -E --ask=no --pretend
run 'overlay-clean/missing'      -O /tmp/udept-nonexistent-overlay-$$
