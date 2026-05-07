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
load_dep() {
	set --
	# bats runs with set -e; dep.in uses '((counter++))' patterns that
	# return non-zero when the pre-increment value is 0, which would
	# abort sourcing under errexit. Disable around the source.
	local was_errexit=
	[[ $- == *e* ]] && was_errexit=1
	set +e
	# shellcheck source=../../src/dep.in
	source "${BATS_TEST_DIRNAME}/../../src/dep.in"
	[[ $was_errexit ]] && set -e
	return 0
}
