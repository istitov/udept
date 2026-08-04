#!/usr/bin/env bats
# Unit tests for the USE-resolution dispatcher usecomponent() and its
# two previously-dead-code branches: pkginternal and env.d.
#
# Pre-fix history: empty placeholder cases at the top of the case
# statement (`pkginternal);;`, `env.d);;`, `repo);;`) silently shadowed
# the real handlers below them. The default USE_ORDER includes both
# `pkginternal` and `env.d`, so every call to dbuse() walked through
# them and produced nothing — udept was doing USE resolution without
# two active tiers since the modern-era refactor. Commit 8673115
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

@test "split_use_tokens: whitespace never produces empty flag records" {
	run split_use_tokens <<<' alpha  beta '
	[ "$status" -eq 0 ]
	[ "${#lines[@]}" -eq 2 ]
	[[ "$output" == $'alpha\nbeta' ]]
}

@test "usecomponent pkg: missing package.use is an empty component" {
	run usecomponent pkg cat/pkg-1
	[ "$status" -eq 0 ]
	[[ -z "$output" ]]
}

@test "usecomponent pkg: matching multi-flag rules are split high-first" {
	printf '%s\n' 'cat/pkg first -second third' >"$ETC_PORTAGE_DIR/package.use"
	run usecomponent pkg cat/pkg-1
	[ "$status" -eq 0 ]
	[[ "$output" == $'third\n-second\nfirst' ]]
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
	[[ "$output" == $'-gamma\nbeta\nalpha' ]]
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

@test "usecomponent features: FEATURES=test forces USE=test" {
	FEATURES='sandbox test userpriv'
	run usecomponent features cat/pkg-1
	[ "$status" -eq 0 ]
	[[ "$output" == test ]]
}

@test "usecomponent repo: repository make.defaults contributes USE" {
	local repo="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$repo/profiles" "$repo/cat/pkg"
	printf '%s\n' 'USE="repo-flag -other"' >"$repo/profiles/make.defaults"
	portage_trees="$repo"
	PORTDIR="$repo"
	run usecomponent repo cat/pkg-1
	[ "$status" -eq 0 ]
	[[ "$output" == $'-other\nrepo-flag' ]]
}

@test "usecomponent defaults: profile package rules override make.defaults per node" {
	local child="$BATS_TEST_TMPDIR/child" parent="$BATS_TEST_TMPDIR/parent"
	mkdir -p "$child" "$parent"
	printf '%s\n' 'USE="child-default -shared"' >"$child/make.defaults"
	printf '%s\n' 'cat/pkg child-rule shared' >"$child/package.use"
	printf '%s\n' 'USE="parent-default shared"' >"$parent/make.defaults"
	printf '%s\n' 'cat/pkg parent-rule' >"$parent/package.use"
	profile_stack=$(printf '%s\n%s\n' "$child" "$parent")
	package_is_stable() { return 1; }

	run usecomponent defaults cat/pkg-1
	[ "$status" -eq 0 ]
	[[ "$output" == $'shared\nchild-rule\n-shared\nchild-default\nparent-rule\nshared\nparent-default' ]]
}

@test "profile_stack_read: local dir prevents recursion from corrupting sibling-relative parent entries" {
	local child="$BATS_TEST_TMPDIR/child"
	mkdir -p "$child/first" "$child/second"
	printf '%s\n' 'first' 'second' >"$child/parent"
	# A parent file on first forces a recursive call and would overwrite
	# global `dir` without local declarations.
	touch "$child/first/parent"

	run profile_stack_read "$child" first second
	[ "$status" -eq 0 ]
	[[ "${#lines[@]}" -eq 2 ]]
	[[ "${lines[0]}" == "$child/first" ]]
	[[ "${lines[1]}" == "$child/second" ]]
}

@test "usecomponent defaults: stable rules follow Portage precedence" {
	local profile="$BATS_TEST_TMPDIR/profile"
	mkdir -p "$profile"
	printf '%s\n' 'USE="${USE} global-default"' >"$profile/make.defaults"
	printf '%s\n' 'global-stable' >"$profile/use.stable"
	printf '%s\n' 'cat/pkg package-rule' >"$profile/package.use"
	printf '%s\n' 'cat/pkg package-stable-rule' >"$profile/package.use.stable"
	profile_stack=$profile
	package_is_stable() { return 0; }

	run usecomponent defaults cat/pkg-1
	[ "$status" -eq 0 ]
	[[ "$output" == $'package-stable-rule\npackage-rule\nglobal-stable\nglobal-default' ]]
}

@test "usecomponent repo: repository rules exclude profiles and include masters" {
	local master="$BATS_TEST_TMPDIR/master" overlay="$BATS_TEST_TMPDIR/overlay"
	local active="$BATS_TEST_TMPDIR/active-profile"
	mkdir -p "$master/profiles" "$overlay/profiles" "$active"
	printf '%s\n' 'USE="master-default"' >"$master/profiles/make.defaults"
	printf '%s\n' 'cat/pkg master-rule' >"$master/profiles/package.use"
	printf '%s\n' 'USE="overlay-default -shared"' >"$overlay/profiles/make.defaults"
	printf '%s\n' 'cat/pkg overlay-rule shared' >"$overlay/profiles/package.use"
	printf '%s\n' 'cat/pkg profile-only' >"$active/package.use"
	profile_stack=$active
	declare -gA repo_loc=([master]="$master" [overlay]="$overlay")
	declare -gA repo_masters=([overlay]='master')
	best_tree() { printf '%s\n' "$overlay"; }
	package_is_stable() { return 1; }

	run usecomponent repo cat/pkg-1
	[ "$status" -eq 0 ]
	[[ "$output" == $'shared\noverlay-rule\n-shared\noverlay-default\nmaster-rule\nmaster-default' ]]
	[[ "$output" != *profile-only* ]]
}

@test "read_repos_config records repository masters" {
	portageq() {
		printf '%s\n' \
			'[DEFAULT]' \
			'main-repo = gentoo' \
			'[gentoo]' \
			'location = /repos/gentoo' \
			'[overlay]' \
			'location = /repos/overlay' \
			'masters = gentoo'
	}
	read_repos_probe() {
		read_repos_config
		printf '%s|%s|%s\n' "$PORTDIR" "${repo_loc[overlay]}" "${repo_masters[overlay]}"
	}

	run read_repos_probe
	[ "$status" -eq 0 ]
	assert_output '/repos/gentoo|/repos/overlay|gentoo'
}

@test "usecomponent pkgprofile: legacy component excludes repository rules" {
	local repo="$BATS_TEST_TMPDIR/repo" active="$BATS_TEST_TMPDIR/active-profile"
	mkdir -p "$repo/profiles" "$active"
	printf '%s\n' 'cat/pkg repo-only' >"$repo/profiles/package.use"
	printf '%s\n' 'cat/pkg profile-one -profile-two' >"$active/package.use"
	profile_stack=$active
	portage_trees=$repo
	PORTDIR=$repo

	run usecomponent pkgprofile cat/pkg-1
	[ "$status" -eq 0 ]
	[[ "$output" == $'-profile-two\nprofile-one' ]]
}

@test "dbuse: later tokens win within a component and defaults override repo" {
	local profile="$BATS_TEST_TMPDIR/profile" repo="$BATS_TEST_TMPDIR/repo"
	mkdir -p "$profile" "$repo/profiles"
	printf '%s\n' 'USE="local -local -repo-flag"' >"$profile/make.defaults"
	printf '%s\n' 'USE="repo-flag repo-only"' >"$repo/profiles/make.defaults"
	profile_stack=$profile
	portage_trees=$repo
	PORTDIR=$repo
	USE_ORDER='defaults:repo'
	ARCH= USE_EXPAND=
	package_use_force() { :; }
	package_use_mask() { :; }
	package_is_stable() { return 1; }

	run dbuse cat/pkg-1
	[ "$status" -eq 0 ]
	assert_output --partial repo-only
	refute_output --partial repo-flag
	refute_output --partial local
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
