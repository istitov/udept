#!/usr/bin/env bats
# Compatibility-name coverage for the shared EAPI 8 atom matcher.
# Returns 0 on match, 2 if the cp differs (early-out), non-zero on
# any version, slot, repository, or USE mismatch.

load 'test_helper'

setup() {
	load_dep
	VARDB_DIR="$BATS_TEST_TMPDIR/vardb"
	for cpv in cat/pkg-1.0 cat/pkg-1.5; do
		mkdir -p "$VARDB_DIR/$cpv"
		printf '%s\n' '0/2' >"$VARDB_DIR/$cpv/SLOT"
		printf '%s\n' 'foo bar baz' >"$VARDB_DIR/$cpv/IUSE"
		printf '%s\n' 'foo' >"$VARDB_DIR/$cpv/USE"
	done
	# Consumed dynamically by atom_use_satisfies from the sourced script.
	# shellcheck disable=SC2034
	opt_arg_original_depends=yes
}

@test "dep_satisfies: bare cp matches any version" {
	run dep_satisfies 'cat/pkg-1.0' 'cat/pkg'
	assert_success
}

@test "dep_satisfies: '=' exact version matches" {
	run dep_satisfies 'cat/pkg-1.0' '=cat/pkg-1.0'
	assert_success
}

@test "dep_satisfies: '=' wrong version fails" {
	run dep_satisfies 'cat/pkg-1.0' '=cat/pkg-2.0'
	assert_failure
}

@test "dep_satisfies: '>=' with newer cpv satisfies" {
	run dep_satisfies 'cat/pkg-1.5' '>=cat/pkg-1.0'
	assert_success
}

@test "dep_satisfies: '>=' with older cpv fails" {
	run dep_satisfies 'cat/pkg-0.5' '>=cat/pkg-1.0'
	assert_failure
}

@test "dep_satisfies: '<' satisfies for older cpv" {
	run dep_satisfies 'cat/pkg-1.5' '<cat/pkg-2.0'
	assert_success
}

@test "dep_satisfies: '<' fails for equal cpv" {
	run dep_satisfies 'cat/pkg-2.0' '<cat/pkg-2.0'
	assert_failure
}

@test "dep_satisfies: '<=' satisfies for equal cpv" {
	run dep_satisfies 'cat/pkg-2.0' '<=cat/pkg-2.0'
	assert_success
}

@test "dep_satisfies: '~' matches any revision of same -version" {
	run dep_satisfies 'cat/pkg-1.2-r3' '~cat/pkg-1.2'
	assert_success
}

@test "dep_satisfies: '~' fails for different version" {
	run dep_satisfies 'cat/pkg-1.3' '~cat/pkg-1.2'
	assert_failure
}

@test "dep_satisfies: '=cat/pkg-2*' glob matches 2.x" {
	run dep_satisfies 'cat/pkg-2.5.1' '=cat/pkg-2*'
	assert_success
}

@test "dep_satisfies: '=cat/pkg-2*' glob rejects 3.x" {
	run dep_satisfies 'cat/pkg-3.0' '=cat/pkg-2*'
	assert_failure
}

@test "dep_satisfies: different cp returns 2 (early-out)" {
	run dep_satisfies 'cat/pkg-1.0' 'cat/other'
	assert_equal "$status" 2
}

@test "dep_satisfies: slot suffix ':0' is enforced" {
	run dep_satisfies 'cat/pkg-1.0' '=cat/pkg-1.0:0' '0/2'
	assert_success
}

@test "dep_satisfies: slot/sub-slot ':0/2' is enforced" {
	run dep_satisfies 'cat/pkg-1.0' '=cat/pkg-1.0:0/2' '0/2'
	assert_success
}

@test "dep_satisfies: bind-only ':=' accepts any slot" {
	run dep_satisfies 'cat/pkg-1.0' '=cat/pkg-1.0:='
	assert_success
}

@test "dep_satisfies: USE-deps '[foo]' are enforced" {
	run dep_satisfies 'cat/pkg-1.0' 'cat/pkg[foo]'
	assert_success
}

@test "dep_satisfies: complex USE-deps slot and version constraints compose" {
	run dep_satisfies 'cat/pkg-1.5' '>=cat/pkg-1.0:0/2[foo,-bar,baz?]' '0/2'
	assert_success
}

@test "dep_satisfies: revision compared correctly (-r2 > -r1)" {
	run dep_satisfies 'cat/pkg-1.0-r2' '>=cat/pkg-1.0-r1'
	assert_success
}

@test "dep_satisfies: revision compared correctly (-r1 < -r2)" {
	run dep_satisfies 'cat/pkg-1.0-r1' '>=cat/pkg-1.0-r2'
	assert_failure
}
