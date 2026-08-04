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

@test "structured atom parser rejects malformed suffixes and operators" {
	local atom
	for atom in \
		'cat/pkg[foo' 'cat/pkg[]' 'cat/pkg::' 'cat/pkg:' \
		'cat/pkg:::repo' '>=cat/pkg' 'cat/pkg extra' 'cat/pkg/extra'; do
		run atom_parse "$atom"
		assert_failure
	done
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

@test "dep_satisfies_atom: wildcard slot skips slot lookup" {
	slot_for() { printf '%s\n' blocked >"$BATS_TEST_TMPDIR/slot_for_called"; return 1; }
	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg:*'
	assert_success
	[ ! -e "$BATS_TEST_TMPDIR/slot_for_called" ]
}

@test "shared matcher metadata lookup is nounset-safe" {
	set -u
	run dep_satisfies_atom cat/pkg-2.0 '=cat/pkg-2.0:0/2::testrepo'
	set +u
	assert_success
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

@test "conditional USE dependencies parse defaults before evaluating parent state" {
	mkdir -p "$VARDB_DIR/cat/parent-1"
	printf 'missing foo\n' >"$VARDB_DIR/cat/parent-1/IUSE"
	printf 'missing foo\n' >"$VARDB_DIR/cat/parent-1/USE"

	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg[missing(-)?]' '' '' cat/parent-1
	assert_failure
	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg[missing(+)?]' '' '' cat/parent-1
	assert_success
	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg[missing(-)=]' '' '' cat/parent-1
	assert_failure
	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg[!missing(-)?]' '' '' cat/parent-1
	assert_success
	run dep_satisfies_atom cat/pkg-2.0 'cat/pkg[-missing(+)]'
	assert_failure
}

@test "inactive USE conditionals do not load candidate metadata" {
	local queried="$BATS_TEST_TMPDIR/candidate-queried"
	VARDB_DIR="$BATS_TEST_TMPDIR/empty-vardb"
	mkdir -p "$VARDB_DIR"
	dbuse() {
		[[ $1 == cat/parent-1 ]] || printf queried >"$queried"
	}
	extract_var() { printf queried >"$queried"; return 1; }

	run atom_use_satisfies cat/candidate-1 'feature?' cat/parent-1
	assert_success
	assert [ ! -e "$queried" ]
}

@test "multilib conditional USE group remains matchable" {
	local abi_flags='abi_mips_n32 abi_mips_n64 abi_mips_o32 abi_s390_32 abi_s390_64 abi_x86_32 abi_x86_64 abi_x86_x32'
	printf '%s\n' "$abi_flags" >"$VARDB_DIR/cat/pkg-2.0/IUSE"
	printf 'abi_x86_64\n' >"$VARDB_DIR/cat/pkg-2.0/USE"
	mkdir -p "$VARDB_DIR/cat/parent-1"
	printf '%s\n' "$abi_flags" >"$VARDB_DIR/cat/parent-1/IUSE"
	printf 'abi_x86_64\n' >"$VARDB_DIR/cat/parent-1/USE"

	run dep_satisfies_atom cat/pkg-2.0 \
		'cat/pkg[abi_mips_n32(-)?,abi_mips_n64(-)?,abi_mips_o32(-)?,abi_s390_32(-)?,abi_s390_64(-)?,abi_x86_32(-)?,abi_x86_64(-)?,abi_x86_x32(-)?]' \
		'' '' cat/parent-1
	assert_success
}

@test "_smartdep retains a revdep whose atom uses a conditional default" {
	mkdir -p "$VARDB_DIR/cat/parent-1"
	printf 'foo\n' >"$VARDB_DIR/cat/parent-1/IUSE"
	printf 'foo\n' >"$VARDB_DIR/cat/parent-1/USE"
	WORLD_FILE="$BATS_TEST_TMPDIR/world"
	: >"$WORLD_FILE"
	allprofilepackages=

	provided_mlsrs() { printf '2.0\n'; }
	avail_versions() { printf '2.0\n'; }
	potential_revdepends() { printf 'cat/parent-1\n'; }
	resdepend() { printf '%s\n' 'cat/pkg[foo(-)?] '; }
	virtuals_from() { :; }
	world_sets_expand() { :; }
	installed_mlsrs() { :; }
	is_running_kernel() { return 1; }

	run _smartdep cat/pkg-2.0
	assert_output 'cat/parent-1 cat/pkg[foo(-)?]'
}

setup_smartdep_repo_case() {
	WORLD_FILE="$BATS_TEST_TMPDIR/world"
	: >"$WORLD_FILE"
	allprofilepackages=
	provided_mlsrs() { printf '2.0\n'; }
	avail_versions() { printf '2.0\n'; }
	potential_revdepends() { printf 'cat/parent-1\n'; }
	virtuals_from() { :; }
	world_sets_expand() { :; }
	is_running_kernel() { return 1; }
}

@test "_smartdep accepts a repository suffix without a slot" {
	setup_smartdep_repo_case
	resdepend() { printf '%s\n' 'cat/pkg::testrepo '; }
	run _smartdep cat/pkg-2.0
	assert_output 'cat/parent-1 cat/pkg::testrepo'
}

@test "_smartdep rejects a malformed triple-colon suffix" {
	setup_smartdep_repo_case
	resdepend() { printf '%s\n' 'cat/pkg:::testrepo '; }
	run _smartdep cat/pkg-2.0
	assert_output ''
}

@test "_smartdep_nopv rejects a malformed triple-colon suffix" {
	setup_smartdep_repo_case
	resdepend() { printf '%s\n' 'cat/pkg:::testrepo '; }
	run _smartdep_nopv cat/pkg
	assert_output ''
}
