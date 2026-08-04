#!/usr/bin/env bats
# Unit tests for the shared matcher's slot primitive and the retained
# dep_satisfies_slot compatibility/test seam.

load 'test_helper'

setup() {
	load_dep
	# Per-test vardb fixture for dep_satisfies_slot's slot_for lookup.
	VARDB_DIR="$BATS_TEST_TMPDIR/vardb"
	mkdir -p "$VARDB_DIR"
}

# Helper: drop a fake installed package with the given SLOT.
fake_install_with_slot() {
	local cpv=$1 slot=$2
	mkdir -p "$VARDB_DIR/$cpv"
	echo "$slot" >"$VARDB_DIR/$cpv/SLOT"
}

# ------------------------------------------------------------------
# slot_satisfies — pure-function tests, no fixture needed
# ------------------------------------------------------------------

@test "slot_satisfies: empty dep_spec matches any pkg_slot" {
	run slot_satisfies '0' ''
	assert_success
	run slot_satisfies '5/2' ''
	assert_success
	run slot_satisfies '' ''
	assert_success
}

@test "slot_satisfies: '=' (bind-only) matches any pkg_slot" {
	run slot_satisfies '0' '='
	assert_success
	run slot_satisfies 'python3_13' '='
	assert_success
}

@test "slot_satisfies: '*' (any-slot) matches any pkg_slot" {
	run slot_satisfies '0' '*'
	assert_success
	run slot_satisfies '5/2' '*'
	assert_success
}

@test "slot_satisfies: bare-name match on plain slot" {
	run slot_satisfies '0' '0'
	assert_success
}

@test "slot_satisfies: bare-name match against pkg_slot with sub-slot" {
	# Common pattern: dep says ':0', pkg has SLOT='0/2' — matches.
	run slot_satisfies '0/2' '0'
	assert_success
}

@test "slot_satisfies: bare-name mismatch" {
	run slot_satisfies '1' '0'
	assert_failure
	run slot_satisfies '2/3' '0'
	assert_failure
}

@test "slot_satisfies: 'NAME=' bind-marker is stripped, then matched" {
	run slot_satisfies '0' '0='
	assert_success
	run slot_satisfies '0/2' '0='
	assert_success
	run slot_satisfies '1' '0='
	assert_failure
}

@test "slot_satisfies: 'NAME/SUB' exact match" {
	run slot_satisfies '0/2' '0/2'
	assert_success
}

@test "slot_satisfies: 'NAME/SUB' fails on sub-slot mismatch" {
	run slot_satisfies '0/3' '0/2'
	assert_failure
}

@test "slot_satisfies: 'NAME/SUB' fails when pkg_slot lacks sub-slot" {
	# We can't prove the sub-slot matches when pkg_slot doesn't carry it.
	run slot_satisfies '0' '0/2'
	assert_failure
}

@test "slot_satisfies: 'NAME/SUB=' bind-marker stripped, exact match" {
	run slot_satisfies '0/2' '0/2='
	assert_success
	run slot_satisfies '0/3' '0/2='
	assert_failure
}

@test "slot_satisfies: empty pkg_slot + non-empty constraint → fail" {
	# Conservative: no slot info, can't prove a match.
	run slot_satisfies '' '0'
	assert_failure
	run slot_satisfies '' '0/2'
	assert_failure
	run slot_satisfies '' '0='
	assert_failure
}

@test "slot_satisfies: empty pkg_slot + any-slot operator → match" {
	# We don't need slot info if the constraint accepts any slot.
	run slot_satisfies '' '*'
	assert_success
	run slot_satisfies '' '='
	assert_success
}

@test "slot_satisfies: named slots (lua5_4, python3_13)" {
	run slot_satisfies 'lua5_4' 'lua5_4'
	assert_success
	run slot_satisfies 'python3_13' 'python3_13'
	assert_success
	run slot_satisfies 'python3_13' 'python3_12'
	assert_failure
}

# ------------------------------------------------------------------
# dep_satisfies_slot — compatibility name for dep_satisfies_atom
# ------------------------------------------------------------------

@test "dep_satisfies_slot: depatom without slot delegates to the shared matcher" {
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg' ''
	assert_success
	run dep_satisfies_slot 'cat/pkg-1.0' '=cat/pkg-1.0' ''
	assert_success
	run dep_satisfies_slot 'cat/pkg-1.0' '=cat/pkg-2.0' ''
	assert_failure
}

@test "dep_satisfies_slot: matching slot, both sides given" {
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:0' '0'
	assert_success
}

@test "dep_satisfies_slot: mismatched slot returns 1" {
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:1' '0'
	assert_failure
	# Specifically, version match succeeds but slot fails — return is 1, not 2.
	[[ "$status" -eq 1 ]]
}

@test "dep_satisfies_slot: cp mismatch returns 2 (slot not consulted)" {
	run dep_satisfies_slot 'cat/pkg-1.0' 'other/thing:0' '0'
	[[ "$status" -eq 2 ]]
}

@test "dep_satisfies_slot: pkg_slot omitted, looked up from vardb" {
	fake_install_with_slot 'cat/pkg-1.0' '2'
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:2'
	assert_success
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:0'
	assert_failure
}

@test "dep_satisfies_slot: pkg_slot omitted, no vardb entry, slotted dep → fail" {
	# No fake_install — slot_for returns empty. Conservative: fail.
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:0'
	assert_failure
}

@test "dep_satisfies_slot: pkg_slot omitted, no vardb, unslotted dep → match" {
	# No slot info needed when depatom has no slot constraint.
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg'
	assert_success
}

@test "dep_satisfies_slot: := operator matches with any pkg_slot" {
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:=' '0'
	assert_success
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:=' 'lua5_4'
	assert_success
}

@test "dep_satisfies_slot: :* operator matches with any pkg_slot" {
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:*' '5/2'
	assert_success
}

@test "dep_satisfies_slot: USE-deps after slot don't disturb slot extraction" {
	fake_install_with_slot 'cat/pkg-1.0' '0'
	printf 'use1 use2\n' >"$VARDB_DIR/cat/pkg-1.0/IUSE"
	printf 'use1\n' >"$VARDB_DIR/cat/pkg-1.0/USE"
	opt_arg_original_depends=yes
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:0[use1,-use2]' '0'
	assert_success
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:1[use1,-use2]' '0'
	assert_failure
}

@test "dep_satisfies_slot: sub-slot in depatom honored" {
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:0/2' '0/2'
	assert_success
	run dep_satisfies_slot 'cat/pkg-1.0' 'cat/pkg:0/3' '0/2'
	assert_failure
}

@test "dep_satisfies_slot: '=' version + ':slot' combined" {
	run dep_satisfies_slot 'cat/pkg-1.5' '>=cat/pkg-1.0:0' '0'
	assert_success
	run dep_satisfies_slot 'cat/pkg-1.5' '>=cat/pkg-1.0:1' '0'
	assert_failure
	run dep_satisfies_slot 'cat/pkg-0.5' '>=cat/pkg-1.0:0' '0'
	assert_failure
}
