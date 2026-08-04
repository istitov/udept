#!/usr/bin/env bats

load 'test_helper'

setup() {
	load_dep
	NO= RD= Gr= FC=
}

@test "format_depatom emits a USE-qualified atom exactly once" {
	local atom='>=dev-libs/icu-51.2-r1:=[abi_x86_32(-)?,abi_x86_64(-)?]'
	run format_depatom "$atom"
	assert_success
	assert_output "$atom"
}

@test "format_depatom preserves blocker slot repository and wildcard syntax" {
	local atom='!!=cat/pkg-2*:0/2=::testrepo[foo,-bar]'
	run format_depatom "$atom"
	assert_success
	assert_output "$atom"
}

@test "format_depatom safely falls back for malformed input" {
	local atom='not-an-atom[still-output-verbatim]'
	run format_depatom "$atom"
	assert_success
	assert_output "$atom"
}
