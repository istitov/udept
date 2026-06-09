#!/usr/bin/env bats
# Property tier: invariants of `dep -E` (filter_etc_portage) over
# package.accept_keywords.
#
# Drives the real keyword filter (package_star_filter + package_keywords_filter)
# end-to-end and asserts idempotence, atom-inventory subset, and no introduced
# duplicate keyword. Synthetic keyword tokens (~testarch / ~otherarch and their
# stable forms) match no real ACCEPT_KEYWORDS on any host, so the fixture
# reveals nothing about this machine's arch; the invariants hold regardless of
# what the host finds redundant.

load 'test_helper'

setup() {
	command -v portageq >/dev/null 2>&1 || skip "needs portageq for redundancy metadata"
	[[ -d /var/db/pkg ]] || skip "needs a populated vardb"
	prop_setup
}

@test "package.accept_keywords: -E is idempotent" {
	printf '%s\n' \
		'# synthetic keywords config' \
		'cat-test/alpha ~testarch' \
		'cat-test/beta ~otherarch testarch' \
		> "$PROP_ETC/package.accept_keywords"

	prop_apply filter_etc_portage
	assert_idempotent filter_etc_portage
}

@test "package.accept_keywords: -E only removes atoms (subset)" {
	printf '%s\n' \
		'cat-test/alpha ~testarch' \
		'cat-test/gamma ~otherarch' \
		> "$PROP_ETC/package.accept_keywords"
	cp -a "$PROP_ETC/package.accept_keywords" "$BATS_TEST_TMPDIR/before"

	prop_apply filter_etc_portage

	assert_atoms_subset "$BATS_TEST_TMPDIR/before" "$PROP_ETC/package.accept_keywords"
}

@test "package.accept_keywords: -E never leaves a duplicate keyword base" {
	printf '%s\n' \
		'cat-test/alpha ~testarch testarch ~testarch' \
		> "$PROP_ETC/package.accept_keywords"

	prop_apply filter_etc_portage

	assert_no_dup_flags "$PROP_ETC/package.accept_keywords"
}
