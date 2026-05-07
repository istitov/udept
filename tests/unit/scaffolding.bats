#!/usr/bin/env bats
# Sanity check for the test harness itself: source dep.in once, confirm a
# basic helper is callable and produces the expected output.

load 'test_helper'

setup() {
	load_dep
}

@test "scaffolding: dep_to_cps is defined after load_dep" {
	declare -F dep_to_cps >/dev/null
}

@test "scaffolding: dep_to_cps passes a bare cat/pkg unchanged" {
	result="$(echo 'cat/pkg' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}
