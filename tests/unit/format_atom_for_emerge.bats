#!/usr/bin/env bats
# Unit tests for format_atom_for_emerge — builds an emerge-feedable atom
# string for a CPV. Default: '=cat/pkg-version'. With --full-atoms (and
# the bash variable opt_arg_full_atoms set): '=cat/pkg-version:slot::repo',
# omitting :slot if SLOT is unavailable and ::repo if no repo is known.
# Sub-slots (':3.13/3.13') are stripped to the major slot only.

load 'test_helper'

setup() {
	load_dep
	# Per-test vardb fixture so each test starts clean.
	VARDB_DIR="$BATS_TEST_TMPDIR/vardb"
	mkdir -p "$VARDB_DIR"
}

# Helper: drop a fake installed package into the per-test VARDB_DIR
# with the given SLOT and (optionally) repository.
fake_install() {
	local cpv=$1 slot=$2 repo=${3-}
	mkdir -p "$VARDB_DIR/$cpv"
	echo "$slot" >"$VARDB_DIR/$cpv/SLOT"
	[[ "$repo" ]] && echo "$repo" >"$VARDB_DIR/$cpv/repository"
	return 0
}

@test "format_atom_for_emerge: default (no flag) emits bare '=cpv'" {
	opt_arg_full_atoms=
	result="$(format_atom_for_emerge 'cat/pkg-1.0')"
	assert_equal "$result" '=cat/pkg-1.0'
}

@test "format_atom_for_emerge: empty cpv emits nothing" {
	result="$(format_atom_for_emerge '' 2>/dev/null || true)"
	assert_equal "$result" ''
}

@test "format_atom_for_emerge: --full-atoms with installed pkg emits :slot::repo" {
	fake_install 'cat/pkg-1.0' '0' 'gentoo'
	opt_arg_full_atoms=1
	result="$(format_atom_for_emerge 'cat/pkg-1.0')"
	assert_equal "$result" '=cat/pkg-1.0:0::gentoo'
}

@test "format_atom_for_emerge: --full-atoms strips sub-slot" {
	fake_install 'cat/pkg-1.0' '3.13/3.13' 'gentoo'
	opt_arg_full_atoms=1
	result="$(format_atom_for_emerge 'cat/pkg-1.0')"
	assert_equal "$result" '=cat/pkg-1.0:3.13::gentoo'
}

@test "format_atom_for_emerge: --full-atoms with non-zero slot" {
	fake_install 'cat/pkg-2.0' '2' 'gentoo'
	opt_arg_full_atoms=1
	result="$(format_atom_for_emerge 'cat/pkg-2.0')"
	assert_equal "$result" '=cat/pkg-2.0:2::gentoo'
}

@test "format_atom_for_emerge: --full-atoms with custom slot string" {
	fake_install 'cat/pkg-1.0' 'lua5_4' 'gentoo'
	opt_arg_full_atoms=1
	result="$(format_atom_for_emerge 'cat/pkg-1.0')"
	assert_equal "$result" '=cat/pkg-1.0:lua5_4::gentoo'
}

@test "format_atom_for_emerge: --full-atoms reads repo from overlay name" {
	fake_install 'cat/pkg-1.0' '0' 'stuff'
	opt_arg_full_atoms=1
	result="$(format_atom_for_emerge 'cat/pkg-1.0')"
	assert_equal "$result" '=cat/pkg-1.0:0::stuff'
}

@test "format_atom_for_emerge: --full-atoms with SLOT but no repository file omits ::repo" {
	# Installed package missing its 'repository' file (older portage),
	# and portage_trees is empty so best_tree has nothing to match.
	# The ::repo suffix is dropped.
	fake_install 'cat/pkg-1.0' '0'
	opt_arg_full_atoms=1
	result="$(format_atom_for_emerge 'cat/pkg-1.0' 2>/dev/null)"
	assert_equal "$result" '=cat/pkg-1.0:0'
}

@test "format_atom_for_emerge: --full-atoms falls back to best_tree+repo_loc for repo lookup" {
	# Older-portage layout: vardb has SLOT but no 'repository' file.
	# Reach the second resolution path: walk portage_trees with
	# best_tree, then reverse-map the matching tree path back through
	# repo_loc[] to recover the repo name.
	fake_install 'cat/pkg-1.0' '0'
	mkdir -p "$BATS_TEST_TMPDIR/overlay/cat/pkg"
	: >"$BATS_TEST_TMPDIR/overlay/cat/pkg/pkg-1.0.ebuild"
	portage_trees="$BATS_TEST_TMPDIR/overlay"
	declare -gA repo_loc=([my_overlay]="$BATS_TEST_TMPDIR/overlay")
	opt_arg_full_atoms=1
	result="$(format_atom_for_emerge 'cat/pkg-1.0' 2>/dev/null)"
	assert_equal "$result" '=cat/pkg-1.0:0::my_overlay'
}

@test "format_atom_for_emerge: --full-atoms with no vardb entry omits :slot and ::repo" {
	# slot_for/extract_var fail (no vardb dir, no portage_trees), best_tree
	# fails (its $PORTDIR fallback is empty here, so 'tree' stays unset and
	# the repo_loc[] reverse-map loop is skipped). Stderr noise is
	# swallowed; stdout is just the bare atom.
	opt_arg_full_atoms=1
	result="$(format_atom_for_emerge 'cat/never-installed-1.0' 2>/dev/null)"
	assert_equal "$result" '=cat/never-installed-1.0'
}

@test "format_atom_for_emerge: --full-atoms preserves -rN revision suffix in cpv" {
	fake_install 'cat/pkg-1.0-r3' '0' 'gentoo'
	opt_arg_full_atoms=1
	result="$(format_atom_for_emerge 'cat/pkg-1.0-r3')"
	assert_equal "$result" '=cat/pkg-1.0-r3:0::gentoo'
}

@test "format_atom_for_emerge: flag off ignores VARDB_DIR fixture" {
	# Even with full vardb data available, the bare-atom path should
	# emit the unadorned form.
	fake_install 'cat/pkg-1.0' '0' 'gentoo'
	opt_arg_full_atoms=
	result="$(format_atom_for_emerge 'cat/pkg-1.0')"
	assert_equal "$result" '=cat/pkg-1.0'
}

@test "format_atom_for_emerge: full atoms delegate repository lookup" {
	slot_for() { printf '%s\n' 0; }
	repo_for_cpv() { printf '%s\n' delegated; }
	opt_arg_full_atoms=1
	result="$(format_atom_for_emerge 'cat/pkg-1.0')"
	assert_equal "$result" '=cat/pkg-1.0:0::delegated'
}
