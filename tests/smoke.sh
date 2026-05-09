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

HEAD_LINES=30      # how many lines of output to embed verbatim per command
CMD_TIMEOUT=120    # cap per-command wall time so a runaway dep walker
                   # doesn't stall the whole harness

# run [-t N] LABEL ARGS...
# -t overrides CMD_TIMEOUT for this single command (used for the slow
# whole-system actions like --depclean).
run() {
	local timeout=$CMD_TIMEOUT
	if [[ "$1" == "-t" ]]; then timeout=$2; shift 2; fi
	local label="$1"; shift
	local out rc lines hash
	out=$(timeout "$timeout" "$DEP" --colour=no "$@" 2>&1)
	rc=$?
	# Strip lines that are inherently unstable across runs but mean
	# nothing for regression detection:
	#   - 'time eval' wall-clock output emitted by '--exec' actions
	#     (lines starting 'real 0m...', 'user ...', 'sys ...').
	#   - 'Return value: N' / 'Return value: N; RESULT: ...' boilerplate
	#     from main()'s exec-action wrapper.
	# These only appear in '--exec' sections in practice but the filter
	# is harmless elsewhere — regular dep output never starts a line
	# with the literal 'real 0m' / 'user 0m' / 'sys 0m' / 'Return value: '
	# patterns. Filtering here (not in smoke-diff.sh) keeps the captured
	# line count and sha256 stable across runs.
	out=$(printf '%s\n' "$out" | sed -E '/^(real|user|sys)[[:space:]]+[0-9]m/d; /^Return value: /d')
	(( rc == 124 )) && out="${out}"$'\n[timed out after '$timeout's]'
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
# Run in a subshell with nullglob so an empty match expands to nothing
# rather than the literal pattern, which keeps `set -u` happy.
pick_glob() {
	(
		shopt -s nullglob
		local g m
		for g in "$@"; do
			local arr=( /var/db/pkg/$g* )
			(( ${#arr[@]} )) && { echo "${arr[0]#/var/db/pkg/}"; exit 0; }
		done
		exit 1
	)
}

PORTAGE=$(pick_glob sys-apps/portage)
BASH_PKG=$(pick_glob app-shells/bash)
PYTHON=$(pick_glob dev-lang/python-3)
GLIBC=$(pick_glob sys-libs/glibc)
VIRTUAL_EDITOR=$(pick_glob virtual/editor)
VIRTUAL_LIBC=$(pick_glob virtual/libc)

# Loud-fail if pick_glob couldn't resolve a required target. set -u
# alone doesn't catch this — the var is *set* by $(), just to an empty
# string when pick_glob's subshell exits 1. Without this guard the
# harness would silently produce 'No matches for ""' rows for every
# command, look like it ran fine, and the resulting snapshot would be
# meaningless. Covers fresh stage3 containers where one of these
# prerequisites hasn't been emerged yet. virtual/editor and virtual/libc
# stay optional — the call sites that use them already guard with
# [[ "$VIRTUAL_..." ]].
for _v in PORTAGE BASH_PKG PYTHON GLIBC; do
	if [[ -z "${!_v}" ]]; then
		echo "FATAL: smoke harness needs $_v resolved (got empty string)" >&2
		echo "Install at least one matching package, or check /var/db/pkg." >&2
		exit 1
	fi
done
unset _v

# A short package-name (PN) for actions that take PNAME
PN_PORTAGE=portage
PN_BASH=bash
PN_PYTHON=python

# A file path likely owned by something. We deliberately pick the LITERAL
# /usr/bin/bash form (not readlink -f resolved) so on a usr-merge system
# this exercises phase 7's alt-prefix / realpath fallback in
# info_action_owners — CONTENTS records /bin/bash, the caller asks
# /usr/bin/bash, the fallback should bridge the two.
if [[ -e /usr/bin/bash ]]; then
	OWNED_FILE=/usr/bin/bash
elif [[ -e /bin/bash ]]; then
	OWNED_FILE=/bin/bash
else
	OWNED_FILE=$(command -v bash || echo /bin/bash)
fi

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
run 'changelog/portage'       --changelog=3 "$PN_PORTAGE"
run 'usedesc/portage'         -u "$PORTAGE"
run 'iuse/python'             -U python
run 'size/portage'            -z "$PORTAGE"
run 'search/portage'          -g portage
run 'owners/file'             -F "$OWNED_FILE"

# --- Virtuals -----------------------------------------------------------
# Strip the trailing -<version> off the cpv we picked from /var/db/pkg
# (e.g. virtual/editor-0-r7 -> virtual/editor) so -R sees a bare cp.
[[ "$VIRTUAL_EDITOR" ]] && run 'virtuals/editor' -R "${VIRTUAL_EDITOR%-[0-9]*}"
[[ "$VIRTUAL_LIBC" ]]   && run 'virtuals/libc'   -R "${VIRTUAL_LIBC%-[0-9]*}"
run 'provides/portage'        -r "$PORTAGE"

# --- Existence probes ----------------------------------------------------
run 'exists/portage:bash'     -x "$PORTAGE" "$PN_BASH"
run 'rev-exists/python:bash'  -X "$PN_PYTHON" "$PN_BASH"

# --- Actions, all read-only / pretend -----------------------------------
# `dep -dp` would shell out to emerge --pretend -C, whose runtime is
# dominated by emerge's own dep graph walk (5+ minutes on a populated
# system). Smoke-testing that mostly tests emerge. Drive the underlying
# redundant() function directly via --exec instead — this is what the
# action would feed to emerge, and exercises our crunch_depends/
# _smartdep paths the same way.
run 'pruneworld/pretend'                  -wp
run 'purge/pretend'                       -Pp
# redundant() emits the cpv list to stdout (what emerge would consume)
# and a parallel cp+mlsr line to stderr (for human display via emerge).
# For a stable smoke snapshot, drop the stderr half.
run -t 300 'depclean/redundant'           --exec 'redundant 2>/dev/null'
run 'filter-etc-portage'                  -E --ask=no --pretend
run 'overlay-clean/missing'               -O /tmp/udept-nonexistent-overlay-$$
