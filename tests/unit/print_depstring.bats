#!/usr/bin/env bats
# Unit tests for print_depstring tokenization of dependency strings.

load 'test_helper'

setup() {
	load_dep
	NO=
}

@test "print_depstring preserves USE default markers while tokenizing" {
	extract_var() { [[ "$1" == DEPEND ]] && printf '%s\n' 'cat/pkg[flag(+)?]'; }
	resolve_depatom() { printf '%s' 'cat/pkg-1.0'; }

	run print_depstring DEPEND cat/pkg-1.0
	[ "$status" -eq 0 ]
	[[ "$output" != *'Invalid depatom'* ]]
	[[ "$output" == *'[flag(+)?]'* ]]
}
