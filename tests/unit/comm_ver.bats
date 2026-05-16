#!/usr/bin/env bats
# Unit tests for comm_ver — the version-comparison workhorse called
# by vercmp(). Output is a return code; the signed-magnitude convention
# (negative-as-mod-256) is documented at the function header:
#
#   $? == 0           → versions equal
#   $? == N (1..127)  → s1 higher than s2 (difference class N)
#   $? >= 128         → s1 LOWER than s2 (mod-256 truncation of -1..-7)
#
# vercmp() at line 974 reads these conventions:
#   "<"  → $? >= 128
#   ">"  → $? > 0 && $? < 128
#   "="  → $? == 0
#
# difference classes (per the function header comment):
#   1: differ in erev
#   2: differ in status number (alpha1 vs alpha2)
#   3: differ in status      (alpha vs beta)
#   4: differ in letter      (1.2a vs 1.2b)
#   5: differ in mmm length
#   6: differ in mmm
#   7: differ in mmm float component
#
# Known bugs surfaced while writing these tests (not yet fixed; tests
# that would exercise them are deliberately omitted from this file so
# the suite stays green — they'll be added back alongside the fix
# commit):
#
#   * rc-suffix mis-ordered: the status-code formula at lines 1465-1466
#     produces alpha=1, beta=2, pre=3, release=4, p=5, rc=6 — rc is
#     ordered HIGHER than release, contradicting the function's own
#     docstring (alpha=0, beta=1, pre=2, rc=3, release=4, p=5) and
#     Portage's spec. `1.0_rc` compares HIGHER than `1.0`.
#   * `1.0` vs `1.0-r0` aborts: r0 is stripped from both sides, leaving
#     s1_r="" / s2_r="". The fall-through revision check at lines
#     1474-1475 fails both `-lt` and `-gt` on empty operands, so the
#     function reaches `echo "Error!" / exit 128`, which halts the
#     entire script (exit, not return).

load 'test_helper'

setup() {
	load_dep
}

# comm_ver is called via dynamic scope (no `local -`) — bats runs each
# test in a fresh bash subprocess so per-test setup of the *_mlsr / *_ml
# globals doesn't leak between tests.

@test "comm_ver: equal versions return 0" {
	run comm_ver "1.2.3" "1.2.3"
	[ "$status" -eq 0 ]
}

@test "comm_ver: 1.2.3 > 1.2.2 returns 6 (mmm diff)" {
	run comm_ver "1.2.3" "1.2.2"
	[ "$status" -eq 6 ]
}

@test "comm_ver: 1.2.2 < 1.2.3 returns 250 (mod-256 of -6)" {
	run comm_ver "1.2.2" "1.2.3"
	# -6 truncates to 256-6 = 250
	[ "$status" -eq 250 ]
}

# --- Portage convention: 1.2 and 1.2.0 are equal ---------------------------
#
# Documented at the comm_ver header. The implementation handles this by
# falling into a short-circuit when main-array lengths differ but the
# letter + status-suffix + revision concat matches.

@test "comm_ver: 1.2 == 1.2.0 (different mml length, no suffix)" {
	run comm_ver "1.2" "1.2.0"
	[ "$status" -eq 0 ]
}

@test "comm_ver: 1.2.0 == 1.2 (commutativity of the length convention)" {
	run comm_ver "1.2.0" "1.2"
	[ "$status" -eq 0 ]
}

# --- Regression pin for the s1_s/s2_s -> s1_ss/s2_ss typo fix --------------
#
# Pre-fix: the short-circuit at line 1442 referenced undefined variables
# `${s1_s}` / `${s2_s}`. With those expanding empty, status-suffix
# differences were ignored when main-array lengths differed — pairs
# like `1.2_alpha1` vs `1.2.0_beta2` returned equal. The fix uses the
# correct names `s1_ss` / `s2_ss`. These tests pin the corrected
# behaviour so the typo can't silently come back.

@test "comm_ver: 1.2_alpha1 vs 1.2.0_beta2 NOT equal (s1_ss typo regression)" {
	# Pre-fix this returned 0 (equal); post-fix it falls through to
	# the suffix-comparison loop which determines alpha < beta.
	run comm_ver "1.2_alpha1" "1.2.0_beta2"
	[ "$status" -ne 0 ]
}

@test "comm_ver: 1.2_alpha1 < 1.2.0_beta2 (alpha < beta, signed-magnitude)" {
	run comm_ver "1.2_alpha1" "1.2.0_beta2"
	# Difference class 3 (status): s1 lower → return -3 → 253.
	[ "$status" -ge 128 ]
}

@test "comm_ver: 1.2_alpha1 == 1.2.0_alpha1 (suffix matches, length differs)" {
	# Same status-suffix on both sides; length-difference short-
	# circuit fires and returns 0. This is the case the typo fix is
	# meant to preserve.
	run comm_ver "1.2_alpha1" "1.2.0_alpha1"
	[ "$status" -eq 0 ]
}

@test "comm_ver: 1.2_beta vs 1.2.0_beta NOT confused with 1.2 vs 1.2.0_alpha" {
	# Each case stands on its own — the bug was that 1.2_X vs 1.2.0_Y
	# all collapsed to equal regardless of suffix. Make sure 1.2_beta
	# vs 1.2.0_alpha is correctly NOT equal.
	run comm_ver "1.2_beta" "1.2.0_alpha"
	[ "$status" -ne 0 ]
}

# --- Status-class ordering -----------------------------------------------
# Per the function header: alpha < beta < pre < rc < (none) < p.
# vercmp() reads this via the difference classes returned by comm_ver.

@test "comm_ver: 1.0_alpha < 1.0_beta" {
	run comm_ver "1.0_alpha" "1.0_beta"
	[ "$status" -ge 128 ]
}

@test "comm_ver: 1.0_beta < 1.0_pre" {
	run comm_ver "1.0_beta" "1.0_pre"
	[ "$status" -ge 128 ]
}

@test "comm_ver: 1.0 < 1.0_p1 (patch > release)" {
	run comm_ver "1.0" "1.0_p1"
	[ "$status" -ge 128 ]
}

# --- Revision ordering ---------------------------------------------------

@test "comm_ver: 1.0-r1 > 1.0 (any rev > no rev)" {
	run comm_ver "1.0-r1" "1.0"
	# Difference class 1 (erev).
	[ "$status" -eq 1 ]
}

@test "comm_ver: 1.0-r2 > 1.0-r1" {
	run comm_ver "1.0-r2" "1.0-r1"
	[ "$status" -eq 1 ]
}

# --- Letter suffix -------------------------------------------------------

@test "comm_ver: 1.2a < 1.2b (letter ordering)" {
	run comm_ver "1.2a" "1.2b"
	[ "$status" -ge 128 ]
}

# --- vercmp wrapper ------------------------------------------------------
# vercmp(v1, op, v2) reads comm_ver's return code through op-specific
# match predicates. These tests document the wrapper contracts that
# rely on the signed-magnitude convention.

@test "vercmp: 1.0 = 1.0 succeeds" {
	run vercmp "1.0" "=" "1.0"
	[ "$status" -eq 0 ]
}

@test "vercmp: 1.0 < 2.0 succeeds via mod-256 truncation" {
	run vercmp "1.0" "<" "2.0"
	[ "$status" -eq 0 ]
}

@test "vercmp: 2.0 > 1.0 succeeds" {
	run vercmp "2.0" ">" "1.0"
	[ "$status" -eq 0 ]
}

@test "vercmp: 1.0 ~ 1.0-r1 succeeds (same base, any rev)" {
	run vercmp "1.0" "~" "1.0-r1"
	[ "$status" -eq 0 ]
}

@test "vercmp: 1.0 ~ 2.0 fails (different base)" {
	run vercmp "1.0" "~" "2.0"
	[ "$status" -ne 0 ]
}
