#!/usr/bin/env bats
# Unit tests for resolve_depatom — answers 'is this depatom satisfied by
# anything?' and returns the resolved cpv. The function:
#
#   - strips :slot suffixes at entry (defensive, for raw_depends-preserved
#     slots that flow through to slot-agnostic callers)
#   - splits the version operator (=, >=, <=, ~, <, >) out via 'vs'
#   - routes 'cat/pkg' / 'cat/pkg-version' direct to _resolve_depatom_inner
#   - routes bare 'pkg' through pv_to_cpv to recover the category
#   - falls back to virtual resolution when direct lookup fails
#
# These tests stub the underlying helpers (provided_and_avail, pv_to_cpv,
# allvirtuals) so the routing and operator-extraction logic is exercised
# in isolation from the live Portage tree. We call __memoised__resolve_depatom
# directly to bypass the memoise() cache; the cache wrapper is generic
# and not the unit under test.

load 'test_helper'

setup() {
	load_dep
	# Reset state that the helpers leak through globals.
	d_cpv= vs= depatom= installed_only=
	# Default mocks: nothing matches anywhere.
	provided_and_avail() { :; }
	pv_to_cpv() { :; }
	allvirtuals() { :; }
	slot_for() { echo '0/2'; }
}

# Most tests call the un-memoised function directly. Convenience wrapper.
do_resolve() {
	__memoised__resolve_depatom "$@"
}

@test "resolve_depatom: bare cpv with no operator → first mlsr from provided_and_avail" {
	provided_and_avail() { echo "1.0"; echo "0.5"; }
	run do_resolve "cat/pkg"
	assert_success
	assert_output 'cat/pkg-1.0'
}

@test "resolve_depatom: '=' exact-version operator preserved through to mlsr filter" {
	# provided_and_avail returns 2.0 first then 1.0; '=cat/pkg-1.0' should
	# pick 1.0 even though 2.0 is offered first, because dep_satisfies_mlsr
	# narrows to the exact match.
	provided_and_avail() { echo "2.0"; echo "1.0"; }
	run do_resolve "=cat/pkg-1.0"
	assert_success
	assert_output 'cat/pkg-1.0'
}

@test "resolve_depatom: '>=' operator picks first mlsr that satisfies" {
	# Real provided_and_avail emits highest-first (mlsr_sort | tac), so
	# 'first satisfying' equals 'highest satisfying'. Here 2.0 wins.
	provided_and_avail() { echo "2.0"; echo "0.5"; }
	run do_resolve ">=cat/pkg-1.0"
	assert_success
	assert_output 'cat/pkg-2.0'
}

@test "resolve_depatom: '>=' picks highest when multiple satisfy" {
	# All three satisfy >=1.0; 'first wins' from the (highest-first)
	# provided_and_avail order = 2.0. Locks in the dependency on
	# provided_and_avail's mlsr_sort | tac ordering.
	provided_and_avail() { echo "2.0"; echo "1.5"; echo "1.0"; }
	run do_resolve ">=cat/pkg-1.0"
	assert_success
	assert_output 'cat/pkg-2.0'
}

@test "resolve_depatom: '<' operator narrows to satisfying versions" {
	provided_and_avail() { echo "2.0"; echo "0.5"; }
	run do_resolve "<cat/pkg-1.0"
	assert_success
	assert_output 'cat/pkg-0.5'
}

@test "resolve_depatom: '~' (any-revision) operator preserved" {
	# ~cat/pkg-1.0 matches 1.0, 1.0-r1, 1.0-r2 but not 1.1
	provided_and_avail() { echo "1.1"; echo "1.0"; }
	run do_resolve "~cat/pkg-1.0"
	assert_success
	assert_output 'cat/pkg-1.0'
}

@test "resolve_depatom: ':slot' suffix stripped before resolution" {
	# The defensive strip at entry — added in commit 4e5a5fc when raw_depends
	# stopped pre-stripping slots. Without this, _resolve_depatom_inner would
	# try to look up 'cat/pkg:0-...' as a cp and fail.
	provided_and_avail() { echo "1.0"; }
	run do_resolve "cat/pkg:0"
	assert_success
	assert_output 'cat/pkg-1.0'
}

@test "resolve_depatom: ':slot=' (binding op) stripped" {
	provided_and_avail() { echo "1.0"; }
	run do_resolve "cat/pkg:0="
	assert_success
	assert_output 'cat/pkg-1.0'
}

@test "resolve_depatom: ':slot/sub' stripped" {
	provided_and_avail() { echo "1.0"; }
	run do_resolve "cat/pkg:0/2"
	assert_success
	assert_output 'cat/pkg-1.0'
}

@test "resolve_depatom: ':*' any-slot operator stripped" {
	provided_and_avail() { echo "1.0"; }
	run do_resolve "cat/pkg:*"
	assert_success
	assert_output 'cat/pkg-1.0'
}

@test "resolve_depatom: '=' + ':slot' both stripped together" {
	provided_and_avail() { echo "1.0"; }
	run do_resolve "=cat/pkg-1.0:0"
	assert_success
	assert_output 'cat/pkg-1.0'
}

@test "resolve_depatom: bare PN routes through pv_to_cpv" {
	pv_to_cpv() { echo "cat/$1"; }
	provided_and_avail() { echo "1.0"; }
	run do_resolve "pkg"
	assert_success
	assert_output 'cat/pkg-1.0'
}

@test "resolve_depatom: bare PN with multi-category match — first that resolves wins" {
	# pv_to_cpv returns multiple candidates; resolve_depatom takes the first
	# one that successfully resolves. Mock resolves only for the second.
	pv_to_cpv() { echo "cat1/$1"; echo "cat2/$1"; }
	provided_and_avail() {
		# Match only the second category.
		[[ "$1" == "cat2/pkg" ]] && echo "1.0"
	}
	run do_resolve "pkg"
	assert_success
	assert_output 'cat2/pkg-1.0'
}

@test "resolve_depatom: virtual fallback when direct provided_and_avail empty" {
	# Direct lookup: nothing.
	# allvirtuals: 'cat/pkg' is provided by 'virtual/foo'. The virtual
	# resolution path takes over and returns the virtual's cpv.
	provided_and_avail() {
		# When called for cat/pkg → empty; when called for virtual/foo → 1.0
		[[ "$1" == "virtual/foo" ]] && echo "1.0"
	}
	allvirtuals() { echo "cat/pkg virtual/foo"; }
	run do_resolve "cat/pkg"
	assert_success
	assert_output 'virtual/foo-1.0'
}

@test "resolve_depatom: nothing resolves → exit 1 + 'Cannot resolve' error" {
	provided_and_avail() { :; }
	allvirtuals() { :; }
	run do_resolve "definitely/missing-1.0"
	assert_failure
	assert_output --partial 'Cannot resolve depatom'
}
