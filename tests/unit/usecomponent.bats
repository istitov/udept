#!/usr/bin/env bats
# Unit tests for the USE-resolution dispatcher usecomponent() and its
# two previously-dead-code branches: pkginternal and env.d.
#
# Pre-fix history: empty placeholder cases at the top of the case
# statement (`pkginternal);;`, `env.d);;`, `repo);;`) silently shadowed
# the real handlers below them. The default USE_ORDER includes both
# `pkginternal` and `env.d`, so every call to dbuse() walked through
# them and produced nothing — udept was doing USE resolution missing
# two of its six tiers since the modern-era refactor. Commit 8673115
# removed the shadowing placeholders, activating:
#
#   - pkginternal_use_for(cpv): reads IUSE from the cpv's metadata
#     and emits +flag → flag (default-on), -flag → -flag (default-off),
#     bare flag → no output (no opinion from this tier).
#   - env.d: extracts the `export USE='...'` line from profile.env.
#
# These tests pin both tier behaviours so the case-shadow can't come
# back silently. Stubs override extract_var (which pkginternal_use_for
# calls) and write controlled profile.env content for env.d.

load 'test_helper'

# `run --separate-stderr` (used in the env.d missing-file test below)
# requires bats >= 1.5; declaring the minimum quietly suppresses the
# BW02 warning and ensures the harness fails loudly on older bats
# instead of silently producing wrong assertions.
bats_require_minimum_version 1.5.0

setup() {
	load_dep
	# Per-test ETC_PORTAGE_DIR fixture: env.d case reads
	# $ETC_PORTAGE_DIR/profile.env.
	ETC_PORTAGE_DIR="$BATS_TEST_TMPDIR/etc-portage"
	mkdir -p "$ETC_PORTAGE_DIR"
}

# Helper: pin extract_var to a fixed IUSE return for the test.
_stub_extract_var_iuse() {
	# shellcheck disable=SC2317  # called via dynamic name resolution
	extract_var() {
		# Args: $1 = var name, $2 = cpv. We only intercept IUSE.
		[[ "$1" == IUSE ]] && { printf '%s\n' "$FAKE_IUSE"; return 0; }
		return 1
	}
}

# --- pkginternal_use_for direct -------------------------------------------

@test "pkginternal_use_for: '+foo' emits 'foo' (default-on stripped of '+')" {
	FAKE_IUSE='+foo'
	_stub_extract_var_iuse
	run pkginternal_use_for cat/pkg-1.0
	[ "$status" -eq 0 ]
	[[ "$output" == 'foo' ]]
}

@test "pkginternal_use_for: '-foo' emits '-foo' (default-off passed through)" {
	FAKE_IUSE='-foo'
	_stub_extract_var_iuse
	run pkginternal_use_for cat/pkg-1.0
	[ "$status" -eq 0 ]
	[[ "$output" == '-foo' ]]
}

@test "pkginternal_use_for: bare 'foo' emits nothing (no opinion tier)" {
	FAKE_IUSE='foo'
	_stub_extract_var_iuse
	run pkginternal_use_for cat/pkg-1.0
	[ "$status" -eq 0 ]
	[[ -z "$output" ]]
}

@test "pkginternal_use_for: mixed '+a b -c' emits 'a' and '-c'" {
	FAKE_IUSE='+a b -c'
	_stub_extract_var_iuse
	run pkginternal_use_for cat/pkg-1.0
	[ "$status" -eq 0 ]
	# Order matters — IUSE iteration is in source order.
	[[ "$output" == $'a\n-c' ]]
}

@test "pkginternal_use_for: empty IUSE emits nothing" {
	FAKE_IUSE=''
	_stub_extract_var_iuse
	run pkginternal_use_for cat/pkg-1.0
	[ "$status" -eq 0 ]
	[[ -z "$output" ]]
}

# --- usecomponent pkginternal (case-shadow regression pin) ----------------
# These exercise the dispatch through usecomponent that the
# case-shadow bug rendered dead.

@test "usecomponent pkginternal: dispatches to pkginternal_use_for" {
	FAKE_IUSE='+foo -bar'
	_stub_extract_var_iuse
	run usecomponent pkginternal cat/pkg-1.0
	[ "$status" -eq 0 ]
	# Pre-fix this returned empty because the `pkginternal);;`
	# placeholder above the real handler swallowed the dispatch.
	[[ "$output" == $'foo\n-bar' ]]
}

@test "usecomponent pkginternal: empty cpv → no output (guard clause)" {
	FAKE_IUSE='+foo'
	_stub_extract_var_iuse
	# Real handler is `[[ "$cpv" ]] && pkginternal_use_for "$cpv"` —
	# empty cpv short-circuits without calling pkginternal_use_for.
	# The && chain returns non-zero (the falsy [[ "" ]]) but no
	# output is produced. We pin the no-output contract.
	run usecomponent pkginternal ''
	[[ -z "$output" ]]
}

# --- usecomponent env.d (case-shadow regression pin) ----------------------

@test "usecomponent env.d: extracts USE from profile.env" {
	cat >"$ETC_PORTAGE_DIR/profile.env" <<'EOF'
export USE='alpha beta -gamma'
EOF
	run usecomponent env.d ''
	[ "$status" -eq 0 ]
	# Pre-fix this returned empty because the `env.d);;` placeholder
	# above the real handler swallowed the dispatch.
	[[ "$output" == 'alpha beta -gamma' ]]
}

@test "usecomponent env.d: missing profile.env → non-zero exit, no USE output" {
	rm -f "$ETC_PORTAGE_DIR/profile.env"
	# sed writes a "can't read ..." error to stderr and exits 2.
	# `run --separate-stderr` (bats >=1.5) splits stderr into its
	# own $stderr capture so we can cleanly assert that stdout is
	# empty — the contract dbuse / stacking_sort actually relies
	# on. Without --separate-stderr, the sed message would be
	# merged into $output and we'd need a brittle wording-coupled
	# assertion.
	run --separate-stderr usecomponent env.d ''
	[ "$status" -ne 0 ]
	[[ -z "$output" ]]
}

@test "usecomponent env.d: profile.env without 'export USE=' line → empty" {
	cat >"$ETC_PORTAGE_DIR/profile.env" <<'EOF'
export FOO='bar'
export PATH='/usr/bin'
EOF
	run usecomponent env.d ''
	[ "$status" -eq 0 ]
	[[ -z "$output" ]]
}

# --- Phase-4 placeholders ------------------------------------------------
# features and repo are intentional placeholders (TODO at the case site);
# pin their no-op behaviour so a future fix here is deliberate.

@test "usecomponent features: empty output (phase-4 placeholder)" {
	run usecomponent features ''
	[ "$status" -eq 0 ]
	[[ -z "$output" ]]
}

@test "usecomponent repo: empty output (phase-4 placeholder)" {
	run usecomponent repo ''
	[ "$status" -eq 0 ]
	[[ -z "$output" ]]
}

# --- Unknown component ---------------------------------------------------

@test "usecomponent unknown: routes to format_error, no stdout output" {
	# format_error writes to stderr; the `>&2` redirect at the case
	# site means stdout stays empty. We don't pin the exact error
	# wording (would couple to format_error's implementation), just
	# that the unknown branch produces no spurious stdout.
	run usecomponent definitely-not-a-real-component ''
	[[ -z "$output" ]] || [[ "$output" != *foo* ]]
}
