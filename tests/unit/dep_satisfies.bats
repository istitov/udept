#!/usr/bin/env bats
# Unit tests for dep_satisfies — answers 'does CPV satisfy DEPATOM?'
# Returns 0 on match, 2 if the cp differs (early-out), non-zero on
# version mismatch. USE-dep brackets and slot suffixes are stripped
# from the depatom before comparison; we don't filter on either,
# since the bare cat/pkg-version still names the right target.

load 'test_helper'

setup() {
	load_dep
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

@test "dep_satisfies: slot suffix ':0' stripped before compare" {
	run dep_satisfies 'cat/pkg-1.0' '=cat/pkg-1.0:0'
	assert_success
}

@test "dep_satisfies: slot/sub-slot ':0/2' stripped before compare" {
	run dep_satisfies 'cat/pkg-1.0' '=cat/pkg-1.0:0/2'
	assert_success
}

@test "dep_satisfies: slot operator ':=' stripped before compare" {
	run dep_satisfies 'cat/pkg-1.0' '=cat/pkg-1.0:='
	assert_success
}

@test "dep_satisfies: USE-deps '[foo]' stripped before compare" {
	run dep_satisfies 'cat/pkg-1.0' 'cat/pkg[foo]'
	assert_success
}

@test "dep_satisfies: complex USE-deps + slot + version-op stripped" {
	run dep_satisfies 'cat/pkg-1.5' '>=cat/pkg-1.0:0/2[foo,-bar,baz?]'
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
