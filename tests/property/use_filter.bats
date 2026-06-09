#!/usr/bin/env bats
# Property tier: invariants of `dep -E` (filter_etc_portage) over package.use.
#
# Drives the REAL package.use filter (package_star_filter + package_use_filter)
# end-to-end — not the stubbed callback the unit tier uses — and asserts the
# oracle-free invariants that hold regardless of what this host finds
# redundant: idempotence, atom-inventory subset, and no introduced duplicate
# flags. Synthetic atoms (cat-test/*) exercise the not-in-tree removal path; a
# single universal @system package (sys-apps/grep) exercises the real-atom
# path. We assert PROPERTIES, never a host-specific expected output.

load 'test_helper'

setup() {
	command -v portageq >/dev/null 2>&1 || skip "needs portageq for redundancy metadata"
	[[ -d /var/db/pkg ]] || skip "needs a populated vardb"
	prop_setup
}

@test "package.use: -E is idempotent over a mixed real/synthetic fixture" {
	printf '%s\n' \
		'# synthetic test config' \
		'sys-apps/grep pcre nls	# universal real atom' \
		'cat-test/alpha flagx flagy' \
		'cat-test/beta -flagz' \
		> "$PROP_ETC/package.use"

	prop_apply filter_etc_portage          # settle
	assert_idempotent filter_etc_portage   # second run is a no-op
}

@test "package.use: -E only removes atoms (after-set is a subset of before)" {
	printf '%s\n' \
		'sys-apps/grep pcre' \
		'cat-test/alpha flagx' \
		'cat-test/gamma flagy flagz' \
		> "$PROP_ETC/package.use"
	cp -a "$PROP_ETC/package.use" "$BATS_TEST_TMPDIR/before"

	prop_apply filter_etc_portage

	assert_atoms_subset "$BATS_TEST_TMPDIR/before" "$PROP_ETC/package.use"
}

@test "package.use: -E never leaves a duplicate flag base on a line" {
	printf '%s\n' \
		'sys-apps/grep pcre nls' \
		'cat-test/alpha flagx flagy flagx' \
		> "$PROP_ETC/package.use"

	prop_apply filter_etc_portage

	assert_no_dup_flags "$PROP_ETC/package.use"
}
