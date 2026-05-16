# Smoke-test bats helper for udept.
#
# Runs the BUILT src/dep against the real Portage tree on the host (or
# stage3 container in CI). Unlike unit tests — which source dep.in with
# the main dispatch suppressed and stub the Portage primitives — the
# smoke tier validates that the binary actually starts, parses its
# argv, and consumes real eix / qatom / qfile / /var/db/pkg output
# without crashing or panicking on a regression in any of those tools.
#
# Read-only: action-flavor commands (--prune, --purge, --depclean,
# filter-etc, overlay-clean) run with --pretend or against throwaway
# non-existent paths, so no /etc/portage or /var/lib/portage state is
# touched.
#
# Targets (PORTAGE_CPV / BASH_CPV / PYTHON_CPV / ...) are resolved
# lazily from /var/db/pkg on first reference via _resolve_targets;
# require_target() skips the calling @test when the target is not
# installed (covers fresh stage3 containers that don't have, e.g.,
# virtual/editor yet).

# Path to the built binary. Tests resolve it from BATS_TEST_DIRNAME so
# this works from any cwd.
DEP_BIN="${BATS_TEST_DIRNAME}/../../src/dep"

# Cap per-command wall time. The reverse-dep tree walks against a
# populated tree can fork hundreds of dep subprocesses; without a cap a
# regression that produces an infinite walk would stall CI for hours.
# 120s matches the smoke.sh harness; depclean overrides to 300s.
DEP_TIMEOUT=120

# Find bats-support / bats-assert. Gentoo installs both under
# /usr/share/bats-{support,assert}/load.bash; some distros use
# /usr/lib. Override BATS_HELPER_DIR if elsewhere.
: "${BATS_HELPER_DIR:=}"
_udept_find_bats_helper() {
	local lib=$1 d
	for d in "${BATS_HELPER_DIR}" /usr/share /usr/lib /usr/lib64 /usr/local/share; do
		[[ "$d" && -f "$d/${lib}/load.bash" ]] && { echo "$d/${lib}/load"; return; }
	done
	echo "ERROR: could not find ${lib}/load.bash; set BATS_HELPER_DIR" >&2
	return 1
}
load "$(_udept_find_bats_helper bats-support)"
load "$(_udept_find_bats_helper bats-assert)"

# Pick first matching cpv from /var/db/pkg. Returns empty string and
# exit 1 if no match. Subshell with nullglob so an unmatched pattern
# expands to nothing instead of the literal glob string.
_pick_cpv() {
	(
		shopt -s nullglob
		local g
		for g in "$@"; do
			local arr=( /var/db/pkg/$g* )
			(( ${#arr[@]} )) && { echo "${arr[0]#/var/db/pkg/}"; exit 0; }
		done
		exit 1
	)
}

# Resolve smoke targets once per bats subprocess. Memoised via
# UDEPT_SMOKE_RESOLVED so repeated invocations from setup() are cheap.
_resolve_targets() {
	[[ "${UDEPT_SMOKE_RESOLVED:-}" ]] && return 0
	PORTAGE_CPV=$(_pick_cpv sys-apps/portage)
	BASH_CPV=$(_pick_cpv app-shells/bash)
	PYTHON_CPV=$(_pick_cpv dev-lang/python-3)
	GLIBC_CPV=$(_pick_cpv sys-libs/glibc)
	VIRTUAL_EDITOR_CPV=$(_pick_cpv virtual/editor)
	VIRTUAL_LIBC_CPV=$(_pick_cpv virtual/libc)
	PN_PORTAGE=portage
	PN_BASH=bash
	PN_PYTHON=python
	# Deliberately the literal /usr/bin/bash path (not readlink -f), so
	# on usr-merge systems this exercises info_action_owners' alt-prefix
	# / realpath fallback (CONTENTS records /bin/bash; caller asks
	# /usr/bin/bash; the fallback must bridge the two).
	if [[ -e /usr/bin/bash ]]; then OWNED_FILE=/usr/bin/bash
	elif [[ -e /bin/bash ]]; then OWNED_FILE=/bin/bash
	else OWNED_FILE=$(command -v bash || echo /bin/bash); fi
	UDEPT_SMOKE_RESOLVED=1
}

# Call from setup() / @test body: skips the test with a clear message
# if the named target variable is empty. PORTAGE / BASH / PYTHON /
# GLIBC are required (loud-fail on resolve in smoke.sh); virtuals and
# the owned-file path are optional.
require_target() {
	_resolve_targets
	local var=$1
	[[ "${!var:-}" ]] || skip "smoke: $var not resolvable on this host"
}

require_dep_built() {
	[[ -x "$DEP_BIN" ]] || skip "src/dep not built; run ./configure && make first"
}

# Strip volatile output for stable assertions. The --exec action wraps
# its eval in `time` and prints a 'Return value: N; RESULT: ...' line
# to stderr; both are noise for smoke assertions. The filter is also
# harmless against non-exec output (regular dep output never matches
# either pattern).
strip_volatile() {
	printf '%s\n' "$1" | sed -E '/^(real|user|sys)[[:space:]]+[0-9]m/d; /^Return value: /d'
}
