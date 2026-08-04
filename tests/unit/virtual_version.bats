#!/usr/bin/env bats

load 'test_helper'

setup() {
	load_dep
	virtuals_from() {
		[[ $1 == app-editors/provider ]] \
			&& printf '%s\n' virtual/editor virtual/other
	}
}

@test "virtual_version returns the provider version for a named virtual" {
	run virtual_version app-editors/provider 3.2-r1 virtual/editor
	assert_success
	assert_output '3.2-r1'
}

@test "virtual_version fails when the package does not provide the virtual" {
	run virtual_version app-editors/provider 3.2-r1 virtual/missing
	assert_failure
	assert_output ''
}
