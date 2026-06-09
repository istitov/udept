#!/usr/bin/env bats
# Regression test for filter_etc_file's comment handling.
#
# Cosmetic/correctness wart: a comment block immediately preceding a dropped
# entry was not cleared, so when the next line (with no blank between) was
# kept, the dropped entry's comment migrated onto it. The fix discards the
# comment block together with the entry it introduced.

load 'test_helper'

setup() {
	load_dep
	temp_dir="$BATS_TEST_TMPDIR"
	ETC_PORTAGE_DIR="$BATS_TEST_TMPDIR/etc"
	mkdir -p "$ETC_PORTAGE_DIR"
	# shellcheck disable=SC2034  # consumed by ask_install_new_file via dynamic scope
	do_action=pretend
}

@test "filter_etc_file: a dropped entry's comment does not migrate to the next kept entry" {
	# No blank line between the dropped and kept entries — the migration case.
	printf '%s\n%s\n%s\n' \
		'# comment for the dropped entry' \
		'cat/dropped flag' \
		'cat/kept flag' \
		>"$ETC_PORTAGE_DIR/package.use"

	# Stub filter: drop any line mentioning 'dropped' (return 1), keep the
	# rest unchanged (empty result + return 0 -> original line echoed).
	# shellcheck disable=SC2317  # called via "${filter[@]}" name-dispatch
	myfilter() { [[ "$1" == *dropped* ]] && return 1; echo ''; }

	# filter_etc_file tees the candidate to $temp_dir/<name>; ask_install_new_file
	# (pretend) just returns. set +e mirrors production (dep.in isn't errexit).
	( set +e; filter_etc_file package.use myfilter ) >/dev/null 2>/dev/null

	run cat "$temp_dir/package.use"
	assert_line --partial 'cat/kept flag'
	refute_line --partial 'comment for the dropped entry'
}

@test "filter_etc_file: a trailing comment block (no blank after it) survives to EOF" {
	# Without the EOF flush, a comment block at end-of-file is dropped:
	# comments are otherwise only emitted on a blank line or when attached
	# to a kept entry, and there is neither after the last one here.
	printf '%s\n%s\n' \
		'cat/kept flag' \
		'# trailing note that must survive' \
		>"$ETC_PORTAGE_DIR/package.use"

	# shellcheck disable=SC2317  # called via "${filter[@]}" name-dispatch
	myfilter() { echo ''; }   # keep every entry

	( set +e; filter_etc_file package.use myfilter ) >/dev/null 2>/dev/null

	run cat "$temp_dir/package.use"
	assert_line --partial 'cat/kept flag'
	assert_line --partial 'trailing note that must survive'
}

@test "filter_etc_file: a comments-only file is not wiped to empty" {
	# Regression: a file with only comments (no entries, no trailing blank)
	# was emptied entirely because the pending comment block was never
	# flushed at EOF.
	printf '%s\n%s\n' \
		'# a standalone note' \
		'# and a second line of it' \
		>"$ETC_PORTAGE_DIR/package.use"

	# shellcheck disable=SC2317  # called via "${filter[@]}" name-dispatch
	myfilter() { echo ''; }

	( set +e; filter_etc_file package.use myfilter ) >/dev/null 2>/dev/null

	run cat "$temp_dir/package.use"
	assert_line --partial 'a standalone note'
	assert_line --partial 'and a second line of it'
}
