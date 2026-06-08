#!/usr/bin/env bats
# Regression test for filter_world's writeback target.
#
# Bug #2 (the literal predates EROOT support; 0.6.0 rebound the READ but not
# the WRITE): filter_world READ ${WORLD_FILE} — which resolve_eroot_paths makes
# EROOT-aware — but passed a hard-coded "/var/lib/portage/world" as the
# ask_install_new_file target. On a non-/ EROOT (Gentoo Prefix / chroot, a
# layout 0.6.0 added support for) `dep -w` in apply mode would therefore prune
# the HOST's world file instead of the target root's. The fix passes
# "$WORLD_FILE", so the write follows the same path as the read.

load 'test_helper'

setup() {
	load_dep
	# shellcheck disable=SC2034  # consumed by filter_world via dynamic scope
	temp_dir="$BATS_TEST_TMPDIR"
}

@test "filter_world: writeback target follows \$WORLD_FILE (EROOT-aware), not a hard-coded path" {
	# Simulate a non-/ EROOT world location.
	WORLD_FILE="$BATS_TEST_TMPDIR/eroot/var/lib/portage/world"
	mkdir -p "${WORLD_FILE%/*}"
	: >"$WORLD_FILE"   # empty: the reverse-tree while-loop body never runs

	# print_stats divides by the installed-package count (0 in this harness ->
	# div-by-zero); the real writeback would elevate via doas (Bug #3, a
	# separate issue). Stub both, and spy on the target ask_install_new_file
	# is handed (its 3rd positional argument).
	print_stats() { :; }
	ask_install_new_file() { printf '%s' "$3" >"$BATS_TEST_TMPDIR/target_seen"; }

	filter_world
	assert_equal "$(< "$BATS_TEST_TMPDIR/target_seen")" "$WORLD_FILE"
}
