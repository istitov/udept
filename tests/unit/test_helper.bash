# Shared bats setup for udept unit tests.
#
# Usage from a .bats file:
#
#   load 'test_helper'
#   setup_file() { load_dep; }
#
# bats_load_library is bats >= 1.7. Helpers come from
# dev-util/bats-support and dev-util/bats-assert (both at
# /usr/share/bats-*/load.bash on Gentoo).

# Find the bats helper libraries. dev-util/bats-support and bats-assert
# install to /usr/share on Gentoo and most distros; some put them under
# /usr/lib. Override BATS_HELPER_DIR to point elsewhere.
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

# Source src/dep.in safely.
#   - 'set --' clears positional args so the script's top-level option
#     parser doesn't choke on the bats runner's argv.
#   - $0 is the bats test runner here (something like '.../bats-exec-test'),
#     not '*/dep', so the two `[[ "$0" == */dep ]]` guards in the script
#     don't fire — main() is not called and load_portage_config / portageq
#     are not invoked at source time.
#
# Test isolation note: bats spawns a fresh bash subprocess per @test, so
# the script-level 'temp_dir="$(mktemp ...)"' on dep.in:537 produces a
# distinct temp_dir per test. memoise() caches into $temp_dir, so cached
# results from one test don't leak into another even though several
# tested helpers (best_tree, world_sets_expand, resolve_depatom, ...) are
# memoised. If bats ever shares a process across tests, that isolation
# breaks and tests using fixtures will need to clear $temp_dir/<fn>/
# explicitly in setup().
load_dep() {
	# Save bats's traps before sourcing — dep.in installs its own
	# EXIT/TERM traps for tempdir cleanup (line ~558) which would
	# replace bats's EXIT trap (`bats_exit_trap`) used for result
	# reporting, and dep.in's top-level execution fires the bats
	# ERR trap (`bats_error_trap`) because of patterns like
	# `((counter++))` that return non-zero on the pre-increment.
	# Without these snapshots restored after the source, failing
	# bats assertions silently drop from the TAP report — the test
	# is counted but neither `ok` nor `not ok` is emitted (bats
	# prints `Executed M instead of expected N tests` and exits 1,
	# which catches the regression in CI but obscures WHICH test
	# failed).
	local _bats_exit_trap _bats_term_trap _bats_err_trap
	_bats_exit_trap=$(trap -p EXIT)
	_bats_term_trap=$(trap -p TERM)
	_bats_err_trap=$(trap -p ERR)
	# Optional arguments let parser-focused tests source dep.in with a
	# deliberate argv; ordinary callers pass none and retain the historical
	# empty argument list.
	set -- "$@"
	# bats runs with set -e; dep.in uses '((counter++))' patterns that
	# return non-zero when the pre-increment value is 0, which would
	# abort sourcing under errexit. Disable around the source. Also
	# clear ERR so the source's non-zero lines don't trip bats's
	# ERR-trap test-fail handler before we restore it.
	local was_errexit=
	[[ $- == *e* ]] && was_errexit=1
	set +e
	trap - ERR
	# shellcheck source=../../src/dep.in
	source "${BATS_TEST_DIRNAME}/../../src/dep.in"
	[[ $was_errexit ]] && set -e
	# Drop dep.in's EXIT/TERM, restore bats's EXIT/TERM/ERR.
	trap - EXIT TERM
	eval "$_bats_exit_trap"
	eval "$_bats_term_trap"
	eval "$_bats_err_trap"
	return 0
}
