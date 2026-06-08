#!/usr/bin/env bats
# Regression test for install_new_file's privilege handling.
#
# Bug #3: when EUID != 0, install_new_file ALWAYS escalated via doas/sudo/su,
# even when the target was already writable by the current user — causing
# spurious password prompts and root-owned files when dep runs against a
# user-owned tree (a non-root EROOT, a test sandbox, ...). The fix writes
# directly when the target (or its parent dir, for a new file) is writable,
# and escalates only when it genuinely isn't.

load 'test_helper'

setup() {
	load_dep
}

@test "install_new_file: non-root + writable target -> direct write, no escalation" {
	[[ $EUID -eq 0 ]] && skip "must run as non-root to exercise the escalation guard"

	# If escalation is (wrongly) attempted, these record it and fail the
	# write (return 2 -> install_new_file's loop returns 1). command -v
	# finds shell functions, so install_new_file will pick one of these.
	local flag="$BATS_TEST_TMPDIR/escalated"
	doas() { echo called >"$flag"; return 2; }
	sudo() { echo called >"$flag"; return 2; }
	su()   { echo called >"$flag"; return 2; }

	local target="$BATS_TEST_TMPDIR/world"
	: >"$target"                              # exists, writable by us
	printf 'NEW CONTENT\n' >"$BATS_TEST_TMPDIR/new"

	run install_new_file "$BATS_TEST_TMPDIR/new" "$target"
	assert_success
	assert_equal "$(cat "$target")" "NEW CONTENT"
	assert [ ! -f "$flag" ]                   # escalation tool never invoked
}

@test "install_new_file: non-root + new file in a writable dir -> direct write" {
	[[ $EUID -eq 0 ]] && skip "must run as non-root to exercise the escalation guard"

	local flag="$BATS_TEST_TMPDIR/escalated"
	doas() { echo called >"$flag"; return 2; }
	sudo() { echo called >"$flag"; return 2; }
	su()   { echo called >"$flag"; return 2; }

	local target="$BATS_TEST_TMPDIR/newdir/world"   # does not exist yet
	mkdir "$BATS_TEST_TMPDIR/newdir"                 # parent writable by us
	printf 'FRESH\n' >"$BATS_TEST_TMPDIR/new"

	run install_new_file "$BATS_TEST_TMPDIR/new" "$target"
	assert_success
	assert_equal "$(cat "$target")" "FRESH"
	assert [ ! -f "$flag" ]
}
