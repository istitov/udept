#!/usr/bin/env bats
# Regression tests for ask_install_new_file under --pretend (do_action=pretend).
#
# Bug #1 (present since the 2005 import — dep.in initial commit): the --pretend
# branch ran `exit 0` whenever the candidate file differed from the original.
# filter_etc_portage calls filter_etc_file -> ask_install_new_file once per
# /etc/portage file (package.use, package.mask, package.accept_keywords,
# bashrc, ...), so that exit terminated the WHOLE process at the first file
# with redundant entries. Every later file was silently skipped, and
# `dep --filter-etc-portage --pretend` printed a truncated preview that looked
# complete. The fix returns instead of exiting.
#
# Each call runs inside $(...) so a stray `exit` (the bug) ends only the
# subshell; the trailing marker is captured iff control RETURNED from the
# function rather than exiting.

load 'test_helper'

setup() {
	load_dep
	temp_dir="$BATS_TEST_TMPDIR"
	# shellcheck disable=SC2034  # consumed by ask_install_new_file via dynamic scope
	do_action=pretend
}

@test "ask_install_new_file --pretend: differing files -> returns (no exit), no write" {
	printf 'kept\ndropped\n' >"$temp_dir/old"
	printf 'kept\n'          >"$temp_dir/new"
	local out
	out=$(
		ask_install_new_file "$temp_dir/old" "$temp_dir/new" "$temp_dir/target" "test file"
		# Reached only if the function RETURNED (Bug #1 exited here instead).
		printf 'returned; target-exists=%s' "$([[ -e $temp_dir/target ]] && echo yes || echo no)"
	)
	assert_equal "$out" "returned; target-exists=no"
}

@test "ask_install_new_file --pretend: identical files -> early return, no write" {
	printf 'same\n' >"$temp_dir/old"
	printf 'same\n' >"$temp_dir/new"
	local out
	out=$(
		ask_install_new_file "$temp_dir/old" "$temp_dir/new" "$temp_dir/target" "test file"
		printf 'returned; target-exists=%s' "$([[ -e $temp_dir/target ]] && echo yes || echo no)"
	)
	assert_equal "$out" "returned; target-exists=no"
}

# Workflow-level regression: drive the real filter_etc_portage ->
# filter_etc_file -> ask_install_new_file walk over three fixture files.
# The per-line filter callbacks are stubbed to "drop everything" (the walk
# is what's under test; the real callbacks need live vardb). Pre-fix, the
# `exit 0` killed the process at the first changed file (package.use), so
# package.mask and package.accept_keywords were never checked.
@test "filter_etc_portage --pretend walks every file, not just the first changed one" {
	ETC_PORTAGE_DIR="$BATS_TEST_TMPDIR/etc/portage"
	mkdir -p "$ETC_PORTAGE_DIR"
	printf 'cat/a flag\n'   >"$ETC_PORTAGE_DIR/package.use"
	printf 'cat/b\n'        >"$ETC_PORTAGE_DIR/package.mask"
	printf 'cat/c ~amd64\n' >"$ETC_PORTAGE_DIR/package.accept_keywords"
	# shellcheck disable=SC2317  # called via "${filter[@]}" name-dispatch in filter_etc_file
	package_star_filter() { return 1; }   # drop every line -> file differs
	# shellcheck disable=SC2317
	package_mask_filter() { return 1; }
	# Subshell contains a stray exit (the bug); set +e mirrors production
	# (dep.in does not run under errexit). "Checking ..." lines go to stderr.
	local err="$BATS_TEST_TMPDIR/err"
	( set +e; filter_etc_portage ) >/dev/null 2>"$err"
	grep -q 'package\.use'             "$err"
	grep -q 'package\.mask'            "$err"
	grep -q 'package\.accept_keywords' "$err"
}
