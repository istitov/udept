#!/usr/bin/env bats

load 'test_helper'

@test "action mode defaults to dry run" {
	load_dep
	assert_equal "$do_action" pretend
	assert_equal "$portage_action_arg" --pretend
}

@test "--ask selects interactive mode" {
	load_dep --ask --exec true
	assert_equal "$do_action" ask
	assert_equal "$portage_action_arg" --ask
}

@test "--force selects execution mode" {
	load_dep --force --exec true
	assert_equal "$do_action" force
	assert_equal "$portage_action_arg" ''
}

@test "action modes are mutually exclusive" {
	load_dep --pretend --force --exec true
	assert_equal "$do_arg_action" usage
	assert_equal "$arg_error" '--pretend, --ask, and --force are mutually exclusive'
}
