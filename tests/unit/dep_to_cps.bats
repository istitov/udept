#!/usr/bin/env bats
# Unit tests for dep_to_cps — reads a DEPEND-string token soup on stdin
# and emits one bare 'cat/pkg' per line, sorted unique. Strips USE-deps,
# slot suffixes, version operators, version, blockers, and control
# tokens (||, parens, use? markers).

load 'test_helper'

setup() {
	load_dep
}

@test "dep_to_cps: bare cat/pkg unchanged" {
	result="$(echo 'cat/pkg' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: '=' version operator stripped" {
	result="$(echo '=cat/pkg-1.2' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: '>=' with revision stripped" {
	result="$(echo '>=cat/pkg-1.2-r1' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: '~' approximate version stripped" {
	result="$(echo '~cat/pkg-1.2' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: '<' upper-bound stripped" {
	result="$(echo '<cat/pkg-1.0' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: '*' glob version stripped" {
	result="$(echo '=cat/pkg-1.2*' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: simple slot ':0' stripped" {
	result="$(echo 'cat/pkg:0' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: slot/sub-slot ':0/2' stripped" {
	result="$(echo 'cat/pkg:0/2' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: slot operator ':=' stripped" {
	result="$(echo 'cat/pkg:=' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: USE-dep brackets '[foo,-bar]' stripped" {
	result="$(echo 'cat/pkg[foo,-bar]' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: complex USE-deps stripped" {
	result="$(echo 'cat/pkg[foo,-bar,baz?,quux=,(+)]' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: combined version + slot + USE-deps" {
	result="$(echo '>=cat/pkg-1.2:0/2[foo,-bar]' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: single-bang blocker '!' stripped" {
	result="$(echo '!cat/pkg' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: double-bang blocker '!!=cat/pkg-1.0' stripped" {
	result="$(echo '!!=cat/pkg-1.0' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: '||' control token filtered out" {
	result="$(echo '|| ( cat/a cat/b )' | dep_to_cps)"
	# Sorted unique → cat/a then cat/b
	expected=$'cat/a\ncat/b'
	assert_equal "$result" "$expected"
}

@test "dep_to_cps: 'use?' conditional marker filtered out" {
	result="$(echo 'foo? ( cat/pkg )' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: '!use?' negated conditional marker filtered out" {
	result="$(echo '!bar? ( cat/pkg )' | dep_to_cps)"
	assert_equal "$result" 'cat/pkg'
}

@test "dep_to_cps: nested any-of inside use-conditional" {
	result="$(echo 'foo? ( || ( cat/a cat/b ) )' | dep_to_cps)"
	expected=$'cat/a\ncat/b'
	assert_equal "$result" "$expected"
}

@test "dep_to_cps: multiple atoms collapse to sorted-unique cps" {
	result="$(printf '%s\n' 'cat/a' '=cat/b-1.0' 'cat/a:0' '!cat/b' | dep_to_cps)"
	expected=$'cat/a\ncat/b'
	assert_equal "$result" "$expected"
}

@test "dep_to_cps: empty input → empty output" {
	result="$(echo '' | dep_to_cps)"
	assert_equal "$result" ''
}

@test "dep_to_cps: whitespace-only input → empty output" {
	result="$(printf '   \t\n   ' | dep_to_cps)"
	assert_equal "$result" ''
}
