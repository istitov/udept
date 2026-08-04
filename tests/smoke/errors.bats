#!/usr/bin/env bats
# Smoke: error-format probes.
#
# Locks in the shape of error output for unresolvable arguments. Any
# regression that changes the error wording or exit status surfaces
# here. We exercise -l (depends, PACKAGE-typed) against a category/pkg
# that no overlay would ever contain — -l goes through star_arg which
# attempts the lookup; -L (rev-depends, PNAME-typed) would trivially
# pass the unresolved string through to _smartdep_nopv and emit
# nothing, which is less interesting as a regression check.

load test_helper
bats_require_minimum_version 1.5.0

setup() {
	require_dep_built
}

@test "smoke: -l on a nonexistent cat/pkg emits 'No matches' message" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -l definitely/nonexistent
	# Empirically: dep treats unresolvable -l targets as a soft error —
	# emits '!!! No matches for ...' to stdout and exits 0. Locking in
	# this contract; a regression that either makes the error silent
	# OR escalates to a non-zero exit will surface here.
	assert_success
	assert_output --partial 'No matches for'
}

@test "smoke: relative EROOT fails before action dispatch" {
	require_target OWNED_FILE
	run --separate-stderr env EROOT=relative/root \
		"$DEP_BIN" --colour=no -F "$OWNED_FILE"
	[ "$status" -eq 2 ]
	[[ -z "$output" ]]
	[[ "$stderr" == *'EROOT must be absolute'* ]]
}
