#!/usr/bin/env bats
# Property tier: invariants of `dep -w` (filter_world / pruneworld).
#
# filter_world drops world entries whose reverse-tree is empty (nothing
# installed still pulls them in), then rewrites the sorted remainder. Drives it
# end-to-end against a synthetic world file and asserts the oracle-free
# invariants: idempotence (re-pruning the pruned, sorted file is a no-op) and
# inventory subset (pruneworld only removes). Synthetic cat-test/* entries are
# not installed, so the host prunes them; the invariants hold whatever it
# decides.

load 'test_helper'

setup() {
	command -v portageq >/dev/null 2>&1 || skip "needs portageq for reverse-tree metadata"
	[[ -d /var/db/pkg ]] || skip "needs a populated vardb"
	prop_setup
}

@test "world: -w is idempotent" {
	printf '%s\n' \
		'cat-test/alpha' \
		'cat-test/beta' \
		'cat-test/gamma' \
		> "$WORLD_FILE"

	prop_apply filter_world
	assert_idempotent filter_world
}

@test "world: -w only removes entries (after-set is a subset of before)" {
	printf '%s\n' \
		'cat-test/alpha' \
		'cat-test/delta' \
		> "$WORLD_FILE"
	cp -a "$WORLD_FILE" "$BATS_TEST_TMPDIR/before"

	prop_apply filter_world

	assert_atoms_subset "$BATS_TEST_TMPDIR/before" "$WORLD_FILE"
}
