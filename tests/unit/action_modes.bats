#!/usr/bin/env bats

load 'test_helper'

@test "action mode defaults to dry run" {
	load_dep
	assert_equal "$do_action" pretend
	assert_equal "$portage_action_arg" --pretend
}

@test "--ask selects interactive mode" {
	load_dep_with_args --ask --exec true
	assert_equal "$do_action" ask
	assert_equal "$portage_action_arg" --ask
}

@test "--force selects execution mode" {
	load_dep_with_args --force --exec true
	assert_equal "$do_action" force
	assert_equal "$portage_action_arg" ''
}

@test "action modes are mutually exclusive" {
	load_dep_with_args --pretend --force --exec true
	assert_equal "$do_arg_action" usage
	assert_equal "$arg_error" '--pretend, --ask, and --force are mutually exclusive'
}

stub_action_dispatch() {
	resolve_eroot_paths() { :; }
	load_portage_config() { :; }
	set_xterm_title() { :; }
	redundant() { printf '%s\n' cat/redundant-1.0; }
	emerge() { printf '%s\n' "$*"; }
}

@test "-Pp parses and dispatches purge through pretend emerge" {
	load_dep_with_args -Pp
	stub_action_dispatch
	run main
	assert_success
	assert_output '-vC --pretend cat/redundant-1.0'
}

@test "-dp parses and dispatches depclean through pretend emerge" {
	load_dep_with_args -dp
	stub_action_dispatch
	run main
	assert_success
	assert_output '-vC --pretend cat/redundant-1.0'
}
