#!/usr/bin/env bats

load 'test_helper'

setup() {
	load_dep
	VARDB_DIR="$BATS_TEST_TMPDIR/vardb"
	mkdir -p "$VARDB_DIR/cat/pkg-2.0"
	printf '0/2\n' >"$VARDB_DIR/cat/pkg-2.0/SLOT"
	printf 'testrepo\n' >"$VARDB_DIR/cat/pkg-2.0/repository"
	printf 'foo baz\n' >"$VARDB_DIR/cat/pkg-2.0/IUSE"
	printf 'foo\n' >"$VARDB_DIR/cat/pkg-2.0/USE"
	opt_arg_original_depends=yes
}

@test "structured atom parser retains every EAPI 8 constraint" {
	atom_parse '!!>=cat/pkg-2.0:0/2=::testrepo[foo,-baz]'
	assert_equal "$ATOM_BLOCKER" '!!'
	assert_equal "$ATOM_OP" '>='
	assert_equal "$ATOM_CP" 'cat/pkg'
	assert_equal "$ATOM_VERSION" '2.0'
	assert_equal "$ATOM_SLOT" '0/2='
	assert_equal "$ATOM_REPO" testrepo
	assert_equal "$ATOM_USE" 'foo,-baz'
}

@test "shared matcher enforces version slot repository and USE" {
	run dep_satisfies_atom cat/pkg-2.0 '>=cat/pkg-1.0:0/2=::testrepo[foo,-baz]'
	assert_success
	run dep_satisfies_atom cat/pkg-2.0 '>=cat/pkg-1.0:1::testrepo[foo,-baz]'
	assert_failure
	run dep_satisfies_atom cat/pkg-2.0 '>=cat/pkg-1.0:0::other[foo,-baz]'
	assert_failure
	run dep_satisfies_atom cat/pkg-2.0 '>=cat/pkg-1.0:0::testrepo[-foo]'
	assert_failure
}

@test "USE dependency defaults handle flags absent from IUSE" {
	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg[missing(+)]'
	assert_success
	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg[missing(-)]'
	assert_failure
	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg[-missing(-)]'
	assert_success
}

@test "conditional USE dependencies compare parent and candidate state" {
	mkdir -p "$VARDB_DIR/cat/parent-1"
	printf 'foo\n' >"$VARDB_DIR/cat/parent-1/IUSE"
	printf 'foo\n' >"$VARDB_DIR/cat/parent-1/USE"
	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg[foo?]' '' '' cat/parent-1
	assert_success
	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg[!foo=]' '' '' cat/parent-1
	assert_failure
}
