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

@test "install_new_file: replacement is atomic and retains target metadata" {
	local target="$BATS_TEST_TMPDIR/world" new="$BATS_TEST_TMPDIR/new"
	printf 'OLD\n' >"$target"
	printf 'NEW\n' >"$new"
	chmod 0640 "$target"
	touch -t 202001020304.05 "$target"
	local before_mode before_mtime
	before_mode=$(stat -c %a "$target")
	before_mtime=$(stat -c %Y "$target")

	run install_new_file "$new" "$target"
	assert_success
	assert_equal "$(cat "$target")" NEW
	assert_equal "$(stat -c %a "$target")" "$before_mode"
	assert_equal "$(stat -c %Y "$target")" "$before_mtime"
	assert [ -z "$(find "$BATS_TEST_TMPDIR" -name '.world.udept.*' -print -quit)" ]
}

@test "install_new_file: preserves an in-root symlink" {
	mkdir "$BATS_TEST_TMPDIR/root"
	printf 'OLD\n' >"$BATS_TEST_TMPDIR/root/real-world"
	ln -s real-world "$BATS_TEST_TMPDIR/root/world"
	printf 'NEW\n' >"$BATS_TEST_TMPDIR/new"
	UDEPT_WRITE_ROOT="$BATS_TEST_TMPDIR/root"

	run install_new_file "$BATS_TEST_TMPDIR/new" "$BATS_TEST_TMPDIR/root/world"
	assert_success
	assert [ -L "$BATS_TEST_TMPDIR/root/world" ]
	assert_equal "$(cat "$BATS_TEST_TMPDIR/root/real-world")" NEW
}

@test "install_new_file: accepts combined PORTAGE_CONFIGROOT and EPREFIX target" {
	PORTAGE_CONFIGROOT="$BATS_TEST_TMPDIR/config-root"
	EPREFIX='/prefix'
	ETC_PORTAGE_DIR="${PORTAGE_CONFIGROOT}${EPREFIX}/etc/portage"
	mkdir -p "$ETC_PORTAGE_DIR"
	local target="$ETC_PORTAGE_DIR/package.use" new="$BATS_TEST_TMPDIR/new"
	printf 'OLD\n' >"$target"
	printf 'NEW\n' >"$new"

	run install_new_file "$new" "$target"
	assert_success
	assert_equal "$(cat "$target")" NEW
}

@test "install_new_file: rejects dangling and out-of-root symlinks" {
	mkdir "$BATS_TEST_TMPDIR/root"
	printf 'NEW\n' >"$BATS_TEST_TMPDIR/new"
	ln -s missing "$BATS_TEST_TMPDIR/root/dangling"
	ln -s "$BATS_TEST_TMPDIR/outside" "$BATS_TEST_TMPDIR/root/outside-link"
	printf 'OLD\n' >"$BATS_TEST_TMPDIR/outside"
	UDEPT_WRITE_ROOT="$BATS_TEST_TMPDIR/root"

	run install_new_file "$BATS_TEST_TMPDIR/new" "$BATS_TEST_TMPDIR/root/dangling"
	assert_failure
	run install_new_file "$BATS_TEST_TMPDIR/new" "$BATS_TEST_TMPDIR/root/outside-link"
	assert_failure
	assert_equal "$(cat "$BATS_TEST_TMPDIR/outside")" OLD
}

@test "install_new_file: validation failure leaves original intact" {
	local target="$BATS_TEST_TMPDIR/world"
	printf 'OLD\n' >"$target"
	run install_new_file "$BATS_TEST_TMPDIR/missing" "$target"
	assert_failure
	assert_equal "$(cat "$target")" OLD
}
