#!/usr/bin/env bats

load 'test_helper'

setup() {
	load_dep
	local tree="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$tree/virtual/editor"
	: >"$tree/virtual/editor/editor-1.ebuild"
	: >"$tree/virtual/editor/editor-2.ebuild"
	: >"$tree/virtual/editor/editor-3.ebuild"
	: >"$tree/virtual/editor/editor-4.ebuild"
	# Consumed dynamically by allvirtuals from the sourced script.
	# shellcheck disable=SC2034
	portage_trees=$tree
	set_xterm_title() { :; }
	is_package_masked() { [[ $2 == 2 ]]; }
	is_keyword_masked() { [[ $2 == 3 ]]; }
	extract_var() {
		[[ $1 == RDEPEND ]] || return 0
		case $2 in
			virtual/editor-1) printf '%s\n' 'app-editors/visible' ;;
			virtual/editor-2) printf '%s\n' 'app-editors/package-masked' ;;
			virtual/editor-3) printf '%s\n' 'app-editors/keyword-masked' ;;
			virtual/editor-4) printf '%s\n' 'app-editors/second-visible' ;;
		esac
	}
}

@test "allvirtuals includes providers only from visible ebuilds" {
	run __memoised__allvirtuals
	assert_success
	assert_output 'virtual/editor app-editors/second-visible app-editors/visible'
}
