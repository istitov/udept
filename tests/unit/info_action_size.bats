#!/usr/bin/env bats

load 'test_helper'

setup() {
	load_dep
	VARDB_DIR="$BATS_TEST_TMPDIR/vardb"
	mkdir -p "$VARDB_DIR/cat/pkg-1" "$BATS_TEST_TMPDIR/root/a directory"
	printf '12345' >"$BATS_TEST_TMPDIR/root/a file with spaces"
	printf 'xy' >"$BATS_TEST_TMPDIR/root/a directory/target file"
	ln -s 'a directory/target file' "$BATS_TEST_TMPDIR/root/a link"
	cat >"$VARDB_DIR/cat/pkg-1/CONTENTS" <<EOF
obj $BATS_TEST_TMPDIR/root/a file with spaces 0123456789abcdef0123456789abcdef 1
sym $BATS_TEST_TMPDIR/root/a link -> a directory/target file 1
dir $BATS_TEST_TMPDIR/root/a directory
EOF
}

@test "size parser treats whitespace paths as single CONTENTS entries" {
	run info_action_size cat/pkg-1
	assert_success
	assert_output --partial '3 files'
	[[ "$output" != *'inaccessible)'* ]]
}
