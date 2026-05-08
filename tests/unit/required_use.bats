#!/usr/bin/env bats
# Unit tests for the REQUIRED_USE evaluator (eval_ru_list / eval_ru_expr).
# These exercise the grammar in isolation: the caller seeds RU_TOKS,
# RU_ACTIVE, ru_idx, RU_FAIL, then calls eval_ru_list and inspects the
# return code plus RU_FAIL.

load 'test_helper'

setup() {
	load_dep
}

# Helper: run the evaluator over $1 (whitespace-separated tokens) with
# active flags from $2. Sets caller-visible RC and FAILS. bats runs with
# 'set -e' which would abort the helper before we capture $? if
# eval_ru_list returns non-zero — disable errexit around the call.
run_ru() {
	# shellcheck disable=SC2034  # consumed by eval_ru_list via dynamic scope
	RU_TOKS=($1)
	RU_ACTIVE="$2"
	ru_idx=0
	RU_FAIL=()
	set +e
	eval_ru_list
	RC=$?
	set -e
	FAILS="${RU_FAIL[*]}"
}

@test "required-use: bare flag set is satisfied" {
	run_ru 'foo' 'foo bar'
	[[ $RC -eq 0 ]]
	[[ -z "$FAILS" ]]
}

@test "required-use: bare flag missing fails with the flag in RU_FAIL" {
	run_ru 'foo' 'bar baz'
	[[ $RC -eq 1 ]]
	[[ "$FAILS" == 'foo' ]]
}

@test "required-use: !flag holds when flag is unset" {
	run_ru '!foo' 'bar baz'
	[[ $RC -eq 0 ]]
}

@test "required-use: !flag fails when flag is set" {
	run_ru '!foo' 'foo bar'
	[[ $RC -eq 1 ]]
	[[ "$FAILS" == '!foo' ]]
}

@test "required-use: || ( a b ) holds when at least one is set" {
	run_ru '|| ( a b )' 'a'
	[[ $RC -eq 0 ]]
}

@test "required-use: || ( a b ) fails when neither is set" {
	run_ru '|| ( a b )' 'c'
	[[ $RC -eq 1 ]]
	# Diagnostic should preserve the whole clause span
	[[ "$FAILS" == '|| ( a b )' ]]
}

@test "required-use: ^^ ( a b ) holds with exactly one set" {
	run_ru '^^ ( a b )' 'a'
	[[ $RC -eq 0 ]]
}

@test "required-use: ^^ ( a b ) fails when both set" {
	run_ru '^^ ( a b )' 'a b'
	[[ $RC -eq 1 ]]
	[[ "$FAILS" == '^^ ( a b )' ]]
}

@test "required-use: ^^ ( a b ) fails when neither set" {
	run_ru '^^ ( a b )' ''
	[[ $RC -eq 1 ]]
}

@test "required-use: ?? ( a b ) holds with none set" {
	run_ru '?? ( a b )' ''
	[[ $RC -eq 0 ]]
}

@test "required-use: ?? ( a b ) holds with one set" {
	run_ru '?? ( a b )' 'a'
	[[ $RC -eq 0 ]]
}

@test "required-use: ?? ( a b ) fails when both set" {
	run_ru '?? ( a b )' 'a b'
	[[ $RC -eq 1 ]]
}

@test "required-use: cond? ( inner ) skipped when cond unset" {
	run_ru 'cond? ( inner )' 'other'
	[[ $RC -eq 0 ]]
}

@test "required-use: cond? ( inner ) fires when cond set, missing inner fails" {
	run_ru 'cond? ( inner )' 'cond'
	[[ $RC -eq 1 ]]
	[[ "$FAILS" == 'inner' ]]
}

@test "required-use: cond? ( inner ) fires and passes when inner set too" {
	run_ru 'cond? ( inner )' 'cond inner'
	[[ $RC -eq 0 ]]
}

@test "required-use: !cond? ( inner ) fires when cond unset" {
	run_ru '!cond? ( inner )' 'other'
	[[ $RC -eq 1 ]]
	[[ "$FAILS" == 'inner' ]]
}

@test "required-use: !cond? ( inner ) skipped when cond set" {
	run_ru '!cond? ( inner )' 'cond'
	[[ $RC -eq 0 ]]
}

@test "required-use: top-level AND of multiple exprs reports each failure" {
	run_ru 'foo bar' 'foo'
	[[ $RC -eq 1 ]]
	# Both top-level exprs evaluated; only 'bar' fails.
	[[ "$FAILS" == 'bar' ]]
}

@test "required-use: top-level AND with two failures reports both" {
	run_ru 'foo bar' 'baz'
	[[ $RC -eq 1 ]]
	[[ "$FAILS" == 'foo bar' ]]
}

@test "required-use: nested cond? ( || ( a b ) ) holds when || holds" {
	run_ru 'cond? ( || ( a b ) )' 'cond a'
	[[ $RC -eq 0 ]]
}

@test "required-use: nested cond? ( || ( a b ) ) fails when || fails" {
	run_ru 'cond? ( || ( a b ) )' 'cond'
	[[ $RC -eq 1 ]]
	[[ "$FAILS" == '|| ( a b )' ]]
}

@test "required-use: realistic python_targets clause" {
	# Modeled on dev-python/cryptography-46.0.7 et al.
	local clause='|| ( python_targets_pypy3_11 python_targets_python3_11 python_targets_python3_12 python_targets_python3_13 python_targets_python3_14 )'
	run_ru "$clause" 'python_targets_python3_13'
	[[ $RC -eq 0 ]]
}

@test "required-use: realistic python_targets clause unsatisfied" {
	local clause='|| ( python_targets_python3_12 python_targets_python3_13 )'
	run_ru "$clause" 'python_targets_python3_10'
	[[ $RC -eq 1 ]]
	[[ "$FAILS" == "$clause" ]]
}

@test "required-use: empty REQUIRED_USE (nothing to evaluate) succeeds" {
	run_ru '' 'foo bar'
	[[ $RC -eq 0 ]]
	[[ -z "$FAILS" ]]
}

@test "required-use: child failures inside ||(...) don't pollute RU_FAIL" {
	# 'foo' is missing inside ||(), but ||() holds because 'bar' is set.
	# RU_FAIL must NOT contain 'foo' — only the group's truth matters.
	run_ru '|| ( foo bar )' 'bar'
	[[ $RC -eq 0 ]]
	[[ -z "$FAILS" ]]
}
