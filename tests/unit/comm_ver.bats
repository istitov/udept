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
# Two bugs surfaced and were fixed in the 0.7.2 follow-up:
#
#   * rc-suffix mis-ordered: the status-code formula at the suffix
#     loop used to produce alpha=1, beta=2, pre=3, release=4, p=5,
#     rc=6 — rc was ordered HIGHER than release, contradicting both
#     the function's docstring (alpha=0..p=5 with rc=3) and Portage's
#     spec. Replaced with an explicit case statement.
#   * `1.0` vs `1.0-r0` aborted: r0 is stripped from both sides,
#     leaving s1_r="" / s2_r="". The fall-through revision check
#     failed both `-lt` and `-gt` on empty operands, so the function
#     reached its `exit 128` error path and halted the entire script.
#     Fixed by an explicit equality check before the inequality
#     comparisons.

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

@test "comm_ver: 1.0_pre < 1.0_rc (rc above pre)" {
	# Regression pin for the rc-suffix fix: pre-fix rc was placed
	# at scn=6 (above release), so this comparison was inconsistent.
	run comm_ver "1.0_pre" "1.0_rc"
	[ "$status" -ge 128 ]
}

@test "comm_ver: 1.0_rc < 1.0 (release > rc, per Portage spec)" {
	# Regression pin for the rc-suffix fix: pre-fix this returned
	# 6 (rc > release) and downstream vercmp evaluated the wrong
	# answer.  Post-fix rc=3, release=4, so rc < release returns
	# signed -3 -> 253.
	run comm_ver "1.0_rc" "1.0"
	[ "$status" -ge 128 ]
}

@test "comm_ver: 1.0_rc < 1.0_p (p higher than rc)" {
	run comm_ver "1.0_rc" "1.0_p"
	[ "$status" -ge 128 ]
}

@test "comm_ver: 1.0 < 1.0_p1 (patch > release)" {
	run comm_ver "1.0" "1.0_p1"
	[ "$status" -ge 128 ]
}

# --- Revision ordering ---------------------------------------------------

@test "comm_ver: 1.0 == 1.0-r0 (r0 is the default; normalised away)" {
	# Regression pin for the r0-abort fix: pre-fix the function
	# stripped r0 from both sides (leaving s1_r="" / s2_r="") and
	# fell through both `-lt` and `-gt` (both fail on empty
	# operands), reaching `exit 128` — which halted the entire
	# script (exit, not return). Post-fix an explicit equality
	# check before the inequality comparisons catches this case
	# and returns 0.
	run comm_ver "1.0" "1.0-r0"
	[ "$status" -eq 0 ]
}

@test "comm_ver: 1.0-r0 == 1.0 (commutativity of the r0 normalisation)" {
	run comm_ver "1.0-r0" "1.0"
	[ "$status" -eq 0 ]
}

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

# --- Status number ordering ---------------------------------------------
# After the suffix-class compare, comm_ver falls into a numeric compare
# of the digit-portion of the suffix. `-lt`/`-gt` are arithmetic (not
# lexical) so multi-digit numbers compare numerically.

@test "comm_ver: 1.0_alpha1 < 1.0_alpha2" {
	run comm_ver "1.0_alpha1" "1.0_alpha2"
	[ "$status" -ge 128 ]
}

@test "comm_ver: 1.0_alpha10 > 1.0_alpha9 (multi-digit numeric, not lexical)" {
	# `-lt`/`-gt` in `[[ ]]` are arithmetic, so 10 > 9 — not the
	# lexical comparison '10' < '9' that string-compare would give.
	run comm_ver "1.0_alpha10" "1.0_alpha9"
	[ "$status" -eq 2 ]
}

@test "comm_ver: 1.0_alpha01 == 1.0_alpha1 (leading zero normalised)" {
	# The `${s1sci}*(0)` pattern in the suffix-number extraction
	# strips leading zeros, so '01' and '1' both normalise to '1'.
	run comm_ver "1.0_alpha01" "1.0_alpha1"
	[ "$status" -eq 0 ]
}

# --- Letter + status combinations ---------------------------------------
# Letter ordering at the *_l boundary takes precedence over status-suffix
# comparison: a `b` beats an `a` regardless of what follows.

@test "comm_ver: 1.2a_beta < 1.2b_alpha (letter dominates status)" {
	# Pre-letter compare returns first (difference class 4) so the
	# status_class-3 path doesn't fire. Catches regressions where
	# the loop ordering inverted.
	run comm_ver "1.2a_beta" "1.2b_alpha"
	[ "$status" -ge 128 ]
}

@test "comm_ver: 1.2a == 1.2a (letter-only, equal)" {
	run comm_ver "1.2a" "1.2a"
	[ "$status" -eq 0 ]
}

# --- cvs. prefix --------------------------------------------------------
# The legacy `cvs.<digits>` snapshot version syntax. comm_ver's mml split
# treats "cvs" as a leading component; bash arithmetic compares it as 0,
# so two cvs.* versions still compare by their numeric tail.

@test "comm_ver: cvs.1.0 < cvs.1.1 (cvs-prefix snapshot ordering)" {
	run comm_ver "cvs.1.0" "cvs.1.1"
	[ "$status" -ge 128 ]
}

# --- Unknown status suffix ----------------------------------------------
# After the d721e8e + 0.7.2 minor-findings pass, the suffix-class case
# statement triggers format_error + return 128 on an unknown suffix
# (vs the previous silent scn=99 which sorted everything-above-p).
# In practice the suffix parser at line ~1418 only accepts the known
# set, so this path is only reachable if someone extends the parser
# without updating the case statement. We pin the contract anyway.
#
# Constructing an unknown suffix requires bypassing the parser's strip
# step. The parser pattern is
#   *(_@(alpha|beta|pre|rc|p)*([[:digit:]]))
# — so an unknown suffix like '_foo' won't be stripped, won't end up
# in s1_ss, won't reach the case. We can't easily trigger the case-
# '*)' branch from a normal vercmp call; the explicit-error contract
# is documented at the source site instead. No bats test pin for this
# branch — the defense lives in the comment + format_error message.

# --- Format/edge sanity -------------------------------------------------

@test "comm_ver: 1.0_pre vs 1.0_pre1 (suffix-number diff against bare suffix)" {
	# Bare _pre means scn-number = 0 (after the `${s1sci}*(0)` strip);
	# _pre1 means scn-number = 1. So _pre < _pre1.
	run comm_ver "1.0_pre" "1.0_pre1"
	[ "$status" -ge 128 ]
}

@test "comm_ver: unequal suffix-list lengths are nounset-safe" {
	set -u
	run comm_ver 0-r2 0_p999999
	set +u
	[ "$status" -eq 253 ]
}
