#!/usr/bin/env bats
# Property tier: comment-preservation through `dep -E` (filter_etc_portage).
#
# These are the regressions 0.7.4's b6c7044 fixed at the source level — a
# trailing comment block (or a whole comments-only file) silently dropped at
# EOF because comments are otherwise flushed only on a blank line or when
# attached to a kept entry. Here they are asserted as end-to-end invariants of
# the real filter walk, host-independently: a file of only comments and blanks
# has no entries for the metadata-driven filter to remove, so -E must
# reproduce it byte-for-byte.

load 'test_helper'

setup() { prop_setup; }

@test "comments: a file of only comment blocks survives -E byte-for-byte" {
	# Leading block, a blank-separated second block, and a TRAILING block with
	# no blank line after it (the EOF-flush case) — all reproduced exactly.
	printf '%s\n' \
		'# synthetic test config — do not ship' \
		'# second line of the leading block' \
		'' \
		'# a separate block after a blank line' \
		'' \
		'# a trailing block with no blank after it' \
		'# and its second line' \
		> "$PROP_ETC/package.use"

	assert_apply_preserves_file filter_etc_portage package.use
}

@test "comments: a single trailing comment (no trailing blank) is not dropped" {
	printf '%s\n' '# the only line in this file' > "$PROP_ETC/package.use"
	assert_apply_preserves_file filter_etc_portage package.use
}

@test "comments: -E over a comments-only file is idempotent" {
	printf '%s\n' \
		'# block one' \
		'' \
		'# block two at EOF' \
		> "$PROP_ETC/package.use"
	prop_apply filter_etc_portage
	assert_idempotent filter_etc_portage
}
