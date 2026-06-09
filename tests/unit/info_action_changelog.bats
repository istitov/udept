#!/usr/bin/env bats
# Regression test for info_action_changelog's missing-file handling.
#
# Modern Portage trees no longer ship per-package ChangeLog files (the
# history lives in git), so $tree/$cp/ChangeLog typically does not exist.
# The function used to print its "From .../ChangeLog:" header and then read
# the file unconditionally, leaking a raw bash "No such file or directory"
# (with a "dep: line N:" prefix) for every package. The fix guards on the
# file's existence and prints a clean notice instead.

load 'test_helper'

setup() {
	load_dep
}

@test "info_action_changelog: missing ChangeLog -> clean notice, no raw bash error" {
	local repo="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$repo/cat/pkg"          # category/package dir, but NO ChangeLog

	# Stub the repo resolver to point at our fixture tree.
	# shellcheck disable=SC2317  # called indirectly by info_action_changelog
	best_tree() { echo "$repo"; }

	run info_action_changelog "cat/pkg-1.0"
	assert_success
	assert_output --partial 'No ChangeLog available for'
	# The whole point: the unguarded redirect must not fire.
	refute_output --partial 'No such file'
	refute_output --regexp 'line [0-9]+:'
}

@test "info_action_changelog: present ChangeLog is read (guard does not over-trigger)" {
	local repo="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$repo/cat/pkg"
	cat >"$repo/cat/pkg/ChangeLog" <<-'CL'
		*pkg-1.0 (01 Jan 2020)

		  01 Jan 2020; Dev <dev@example.com> pkg-1.0.ebuild:
		  Initial import.
	CL

	# shellcheck disable=SC2317  # called indirectly by info_action_changelog
	best_tree() { echo "$repo"; }

	run info_action_changelog "cat/pkg-1.0"
	assert_success
	assert_output --partial 'ChangeLog'
	refute_output --partial 'No ChangeLog available for'
	refute_output --partial 'No such file'
}
