#!/usr/bin/env bats
# Unit tests for info_action_required-use — the wrapper that drives
# the REQUIRED_USE evaluator end-to-end. eval_ru_list itself is
# covered exhaustively in required_use.bats; these tests verify the
# surrounding plumbing: md5-cache → dbuse → eval → output formatting
# → exit-code propagation via $required_use_violations.
#
# We override extract_var and dbuse so each test pins exact REQUIRED_USE
# and active-USE strings; the action wrapper is the unit under test.

load 'test_helper'

setup() {
	load_dep
	# Plain-text output — color vars off — so assertions compare against
	# literal strings rather than ANSI-bracketed ones.
	NO= GR= RD= BR= BL= YL= CY= FC=
	opt_arg_verbose=0
	required_use_violations=0
}

# Per-test stubs for the two primitives the action calls. Setting
# FAKE_REQUIRED_USE / FAKE_USE in the test body and calling these
# replaces the real dep.in functions for the duration of that bats
# subprocess.
_fake_extract_var_and_dbuse() {
	# shellcheck disable=SC2317  # called via overriding-by-redefinition
	extract_var() {
		[[ "$1" == REQUIRED_USE ]] && printf '%s\n' "$FAKE_REQUIRED_USE" || return 1
	}
	# shellcheck disable=SC2317
	dbuse() { printf '%s\n' "$FAKE_USE"; }
}

@test "info_action_required-use: empty REQUIRED_USE → silent OK, exit 0" {
	FAKE_REQUIRED_USE=""
	FAKE_USE=""
	_fake_extract_var_and_dbuse
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "info_action_required-use: empty REQUIRED_USE + verbose → 'OK (no REQUIRED_USE)'" {
	FAKE_REQUIRED_USE=""
	FAKE_USE=""
	_fake_extract_var_and_dbuse
	opt_arg_verbose=1
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"OK (no REQUIRED_USE)"* ]]
}

@test "info_action_required-use: satisfied bare flag → silent OK" {
	FAKE_REQUIRED_USE="flag1"
	FAKE_USE="flag1 flag2"
	_fake_extract_var_and_dbuse
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "info_action_required-use: satisfied + verbose → 'OK' (no '(no REQUIRED_USE)' suffix)" {
	FAKE_REQUIRED_USE="flag1"
	FAKE_USE="flag1"
	_fake_extract_var_and_dbuse
	opt_arg_verbose=1
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 0 ]]
	[[ "$output" == *"OK"* ]]
	[[ "$output" != *"no REQUIRED_USE"* ]]
}

@test "info_action_required-use: missing required flag → FAIL line, exit 1" {
	FAKE_REQUIRED_USE="missing_flag"
	FAKE_USE="other_flag"
	_fake_extract_var_and_dbuse
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 1 ]]
	[[ "$output" == *FAIL* ]]
	[[ "$output" == *missing_flag* ]]
}

@test "info_action_required-use: ^^ ( a b ) with both set → FAIL, span captured" {
	FAKE_REQUIRED_USE="^^ ( a b )"
	FAKE_USE="a b"
	_fake_extract_var_and_dbuse
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 1 ]]
	[[ "$output" == *FAIL* ]]
	[[ "$output" == *"^^ ( a b )"* ]]
}

@test "info_action_required-use: || ( a b ) with one set → silent OK" {
	FAKE_REQUIRED_USE="|| ( a b )"
	FAKE_USE="a"
	_fake_extract_var_and_dbuse
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "info_action_required-use: increments \$required_use_violations on fail" {
	FAKE_REQUIRED_USE="missing"
	FAKE_USE=""
	_fake_extract_var_and_dbuse
	required_use_violations=0
	# Run in current shell so $required_use_violations updates are visible
	# (run() forks a subshell).
	info_action_required-use 'cat/pkg-1.0' >/dev/null 2>&1 || true
	[[ $required_use_violations -eq 1 ]]
}

@test "info_action_required-use: does NOT increment counter on success" {
	FAKE_REQUIRED_USE="flag1"
	FAKE_USE="flag1"
	_fake_extract_var_and_dbuse
	required_use_violations=0
	info_action_required-use 'cat/pkg-1.0' >/dev/null 2>&1 || true
	[[ $required_use_violations -eq 0 ]]
}

@test "info_action_required-use: cond? ( inner ) skipped → silent OK" {
	FAKE_REQUIRED_USE="missing? ( required )"
	FAKE_USE="other"
	_fake_extract_var_and_dbuse
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 0 ]]
	[[ -z "$output" ]]
}

@test "info_action_required-use: cond? fires with missing inner → FAIL" {
	FAKE_REQUIRED_USE="active? ( required )"
	FAKE_USE="active"
	_fake_extract_var_and_dbuse
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 1 ]]
	[[ "$output" == *FAIL* ]]
	[[ "$output" == *required* ]]
}

@test "info_action_required-use: multiple top-level failures separated by '; '" {
	FAKE_REQUIRED_USE="first second"
	FAKE_USE=""
	_fake_extract_var_and_dbuse
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 1 ]]
	[[ "$output" == *first* ]]
	[[ "$output" == *second* ]]
	[[ "$output" == *"; "* ]]
}

@test "info_action_required-use: extract_var failure (no md5-cache hit) → silent OK" {
	# extract_var returning empty/non-zero is treated as 'no REQUIRED_USE',
	# not as an error — the action is a check, not a probe.
	extract_var() { return 1; }
	dbuse() { echo ""; }
	run info_action_required-use 'cat/pkg-1.0'
	[[ "$status" -eq 0 ]]
}
