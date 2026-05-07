#!/usr/bin/env bats
# Unit tests for world_sets_expand — emits the cpv-list contents of any
# @<set> entry in /var/lib/portage/world_sets, recursively expanding
# @<set> references inside set files. Skips Portage's built-in set names
# (world, selected, profile, ...) and rejects path-traversal attempts.

load 'test_helper'

setup() {
	load_dep
	# Point the function at fixtures we control. bats provides a fresh
	# BATS_TEST_TMPDIR per test.
	WORLD_SETS_FILE="$BATS_TEST_TMPDIR/world_sets"
	ETC_PORTAGE_SETS_DIR="$BATS_TEST_TMPDIR/sets"
	mkdir -p "$ETC_PORTAGE_SETS_DIR"
}

@test "world_sets_expand: missing world_sets file → no output, exit 0" {
	rm -f "$WORLD_SETS_FILE"
	run world_sets_expand
	assert_success
	assert_output ""
}

@test "world_sets_expand: empty world_sets file → no output" {
	: >"$WORLD_SETS_FILE"
	result="$(world_sets_expand)"
	assert_equal "$result" ""
}

@test "world_sets_expand: simple @set expands to its packages" {
	echo "@kde-meta" >"$WORLD_SETS_FILE"
	cat >"$ETC_PORTAGE_SETS_DIR/kde-meta" <<-EOF
		kde-apps/kate
		kde-apps/dolphin
	EOF
	result="$(world_sets_expand)"
	expected=$'kde-apps/kate\nkde-apps/dolphin'
	assert_equal "$result" "$expected"
}

@test "world_sets_expand: nested @set references expand recursively" {
	echo "@meta" >"$WORLD_SETS_FILE"
	cat >"$ETC_PORTAGE_SETS_DIR/meta" <<-EOF
		@inner
		cat/outer
	EOF
	cat >"$ETC_PORTAGE_SETS_DIR/inner" <<-EOF
		cat/a
		cat/b
	EOF
	result="$(world_sets_expand)"
	expected=$'cat/a\ncat/b\ncat/outer'
	assert_equal "$result" "$expected"
}

@test "world_sets_expand: cycle in @set references is broken" {
	echo "@a" >"$WORLD_SETS_FILE"
	cat >"$ETC_PORTAGE_SETS_DIR/a" <<-EOF
		@b
		cat/a-pkg
	EOF
	cat >"$ETC_PORTAGE_SETS_DIR/b" <<-EOF
		@a
		cat/b-pkg
	EOF
	# The seen[] table prevents an infinite loop. Both pkgs appear once.
	result="$(world_sets_expand)"
	expected=$'cat/b-pkg\ncat/a-pkg'
	assert_equal "$result" "$expected"
}

@test "world_sets_expand: comment lines stripped" {
	echo "@s" >"$WORLD_SETS_FILE"
	cat >"$ETC_PORTAGE_SETS_DIR/s" <<-'EOF'
		# this is a comment
		cat/keep        # trailing comment
		# another
		cat/also-keep
	EOF
	result="$(world_sets_expand)"
	expected=$'cat/keep\ncat/also-keep'
	assert_equal "$result" "$expected"
}

@test "world_sets_expand: leading/trailing whitespace stripped" {
	echo "@s" >"$WORLD_SETS_FILE"
	printf '   cat/spaced   \n\t\tcat/tabbed\t\n' >"$ETC_PORTAGE_SETS_DIR/s"
	result="$(world_sets_expand)"
	expected=$'cat/spaced\ncat/tabbed'
	assert_equal "$result" "$expected"
}

@test "world_sets_expand: built-in set names (world) emit nothing" {
	echo "@world" >"$WORLD_SETS_FILE"
	# Even if a 'world' set file exists, the hardcoded skip kicks in first.
	echo "cat/should-not-appear" >"$ETC_PORTAGE_SETS_DIR/world"
	result="$(world_sets_expand)"
	assert_equal "$result" ""
}

@test "world_sets_expand: built-in set 'selected' skipped" {
	echo "@selected" >"$WORLD_SETS_FILE"
	echo "cat/nope" >"$ETC_PORTAGE_SETS_DIR/selected"
	result="$(world_sets_expand)"
	assert_equal "$result" ""
}

@test "world_sets_expand: path-traversal '@../etc/passwd' rejected" {
	echo '@../etc/passwd' >"$WORLD_SETS_FILE"
	# Should not error, should not read /etc/passwd.
	run world_sets_expand
	assert_success
	assert_output ""
}

@test "world_sets_expand: invalid characters in set name rejected" {
	echo '@bad name' >"$WORLD_SETS_FILE"
	# 'bad name' contains a space → fails the [[:alnum:]_-]+ pattern.
	run world_sets_expand
	assert_success
	assert_output ""
}

@test "world_sets_expand: missing referenced set file silently empty" {
	echo "@nonexistent" >"$WORLD_SETS_FILE"
	# No $ETC_PORTAGE_SETS_DIR/nonexistent file → exit 0, no output.
	run world_sets_expand
	assert_success
	assert_output ""
}

@test "world_sets_expand: lines without leading '@' in world_sets ignored" {
	cat >"$WORLD_SETS_FILE" <<-EOF
		cat/this-is-a-package
		@real-set
	EOF
	echo 'cat/from-set' >"$ETC_PORTAGE_SETS_DIR/real-set"
	# Only @-prefixed lines are processed by world_sets_expand.
	result="$(world_sets_expand)"
	assert_equal "$result" 'cat/from-set'
}
