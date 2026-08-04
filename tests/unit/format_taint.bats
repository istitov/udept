#!/usr/bin/env bats
# Unit tests for format_taint: active USE-state coloring for conditional atoms.

load 'test_helper'

setup() {
	load_dep
	# Keep output deterministic; don't depend on real ANSI escapes.
	NO=0
	Rd=R
	RD=R
	BL=B
	Bl=S
}

@test "format_taint: active and inactive conditional USE flags are distinguished" {
	dbuse() { printf '%s\n' active inactive active2; }

	run format_taint cat/pkg-1.0 active? inactive? "!inactive?" "!active2?" other?
	assert_success
	# active  -> RD, !inactive/inactive -> BL, !active2 -> Bl.
	[[ "$output" == 'Ractive0? Rinactive0? S!inactive0? S!active20? Rother0? ' ]]
}
