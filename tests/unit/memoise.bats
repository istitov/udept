#!/usr/bin/env bats

load 'test_helper'

setup() {
	load_dep
	call_log="$BATS_TEST_TMPDIR/calls"
}

@test "memoise does not recreate its cache directory per call" {
	sample_value() {
		printf 'called\n' >>"$call_log"
		printf '%s\n' "$1"
	}
	memoise sample_value
	mkdir() { return 99; }

	run sample_value alpha
	assert_success
	assert_output alpha
	run sample_value alpha
	assert_success
	assert_output alpha
	assert_equal "$(wc -l <"$call_log")" 1
}

@test "memoised predicates hash keys longer than a filesystem component" {
	is_long_key() {
		printf 'called\n' >>"$call_log"
		[[ ${#1} -gt 255 ]]
	}
	memoise_predicate is_long_key
	local key
	printf -v key '%0300d' 0

	run is_long_key "$key"
	assert_success
	run is_long_key "$key"
	assert_success
	assert_equal "$(wc -l <"$call_log")" 1
}

@test "memoised predicates recover from an empty cache entry" {
	is_cached() {
		printf 'called\n' >>"$call_log"
		return 0
	}
	memoise_predicate is_cached
	# Created dynamically by load_dep and consumed by the sourced wrapper.
	# shellcheck disable=SC2154
	: >"$temp_dir/is_cached/_value"

	run is_cached value
	assert_success
	assert_equal "$(wc -l <"$call_log")" 1
	assert_equal "$(<"$temp_dir/is_cached/_value")" 0
}
