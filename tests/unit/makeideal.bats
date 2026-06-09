#!/usr/bin/env bats
# Regression test for makeideal (spring-clean / -s) exit status.
#
# makeideal's last real statement is `[[ "$missing" ]] && emerge -v1 ...`, whose
# status is 1 whenever there is nothing to install. As the function's last
# command that leaked out as `dep -s`'s exit code, so a successful spring-clean
# on an already-tidy system reported failure (exit 1). The fix appends an
# explicit `return 0`.

load 'test_helper'

setup() {
	load_dep
	temp_dir="$BATS_TEST_TMPDIR"
	WORLD_FILE="$BATS_TEST_TMPDIR/world"; : >"$WORLD_FILE"   # empty world
	# shellcheck disable=SC2034  # read by makeideal
	allprofilepackages=""
	# shellcheck disable=SC2034  # read by makeideal
	profileprovided=""
}

@test "makeideal: returns 0 when there is nothing to remove or install" {
	# Nothing installed + empty world/profile => my_redundant and missing are
	# both empty => no emerge is run => the function must still report success.
	# shellcheck disable=SC2317  # invoked inside makeideal
	all_installed_cpvs() { :; }

	run makeideal
	assert_success
}
