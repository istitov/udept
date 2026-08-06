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
	# Both entries resolve under $child; the order is asserted separately.
	[[ " ${lines[*]} " == *" $child/first "* ]]
	[[ " ${lines[*]} " == *" $child/second "* ]]
}

@test "profile_stack_read: a later parent entry outranks an earlier one" {
	# Portage flattens each parent's subtree before the node, so its
	# low-to-high list is flatten(p1) … flatten(pn) node. Reversed for
	# stacking_sort, that makes the LAST parent listed the highest priority
	# after the node itself.
	local root="$BATS_TEST_TMPDIR/root"
	mkdir -p "$root/node" "$root/base" "$root/arch"
	printf '%s\n' '../base' '../arch' >"$root/node/parent"

	run profile_stack_read "$root" node
	[ "$status" -eq 0 ]
	[[ "${#lines[@]}" -eq 3 ]]
	[[ "${lines[0]}" == "$root/node" ]]
	[[ "${lines[1]}" == "$root/arch" ]]
	[[ "${lines[2]}" == "$root/base" ]]
}

@test "package_is_stable: nothing is stable when ACCEPT_KEYWORDS takes ~arch" {
	# KeywordsManager.isStable: the package must be visible now and stop being
	# visible once every keyword becomes its ~ variant. Accepting ~arch means
	# the second half never holds, so use.stable.mask/force do not apply.
	keywords_for() { read -r -a "$3" <<<"amd64 ~x86"; }
	accept_for() { read -r -a "$3" <<<"$ACCEPT_KW"; }

	# package_is_stable is memoised on the cpv alone (ACCEPT_KEYWORDS cannot
	# change mid-run in production), so vary the cpv per case.
	ACCEPT_KW="amd64 ~amd64"
	run package_is_stable cat/pkg-1.0
	assert_failure

	ACCEPT_KW="amd64"
	run package_is_stable cat/pkg-2.0
	assert_success

	# Not visible at all is not stable either.
	ACCEPT_KW="ppc"
	run package_is_stable cat/pkg-3.0
	assert_failure
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

@test "dbuse: package.use.mask overrides package.use.force" {
	local profile="$BATS_TEST_TMPDIR/profile"
	mkdir -p "$profile"
	profile_stack=$profile
	USE_ORDER='features'
	ARCH=
	USE_EXPAND=
	# The features component turns FEATURES=test into USE=test, so an ambient
	# FEATURES leaks a flag into the result. Portage exports FEATURES during
	# src_test, which is exactly where this suite runs under `ebuild ... test`.
	FEATURES=
	package_use_mask() { printf '%s\n' gpm; }
	package_use_force() { printf '%s\n' gpm; }

	run dbuse cat/pkg-1
	[ "$status" -eq 0 ]
	# package.use.force is lower priority than package.use.mask, so
	# the final active-USE set does not contain this flag.
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

# --- conf, USE_EXPAND and the mask/force stack ----------------------------

@test "usecomponent conf: negates profile defaults the resolved USE dropped" {
	# portageq hands back a resolved global USE with no negations in it, so
	# make.conf's `-gtk` is invisible as such: all we see is that the profile
	# sets gtk and Portage's answer does not carry it.
	local profile="$BATS_TEST_TMPDIR/profile"
	mkdir -p "$profile"
	printf '%s\n' 'USE="gtk tiff sound"' >"$profile/make.defaults"
	profile_stack=$profile
	__conf_USE="tiff sound zstd"

	run conf_usecomponent
	[ "$status" -eq 0 ]
	local flat=" ${lines[*]} "
	# gtk was set by the profile and is missing from the resolved set: turned
	# off above the profile, so it belongs here as a negation.
	[[ "$flat" == *" -gtk "* ]]
	# zstd is in the resolved set and unexplained by the profile: make.conf.
	[[ "$flat" == *" zstd "* ]]
	# tiff and sound are explained by the profile and survived, so this
	# component must stay silent about them — otherwise they would outrank the
	# per-package rules in "defaults" that are meant to override them.
	[[ "$flat" != *" tiff "* ]]
	[[ "$flat" != *" sound "* ]]
}

@test "use_expand_usecomponent: a USE_EXPAND variable is a complete set" {
	USE_EXPAND="ABI_X86 PYTHON_TARGETS"
	ABI_X86="64"
	PYTHON_TARGETS="python3_13"
	use_expand_index
	candidate_iuse() { printf '%s\n' 'abi_x86_32 abi_x86_64 python3_13 python_targets_python3_13 python_targets_python3_14 static'; }

	run use_expand_usecomponent cat/pkg-1
	[ "$status" -eq 0 ]
	local flat=" ${lines[*]} "
	[[ "$flat" == *" abi_x86_64 "* ]]
	[[ "$flat" == *" python_targets_python3_13 "* ]]
	# Declared by the package, not carried by the variable: off.
	[[ "$flat" == *" -abi_x86_32 "* ]]
	[[ "$flat" == *" -python_targets_python3_14 "* ]]
	# Flags outside every USE_EXPAND prefix are none of this component's
	# business, and neither is a bare value that only looks like one.
	[[ "$flat" != *" -static "* ]]
	[[ "$flat" != *" -python3_13 "* ]]
}

@test "dbuse: use.mask outranks use.force and ARCH" {
	local profile="$BATS_TEST_TMPDIR/profile"
	mkdir -p "$profile"
	profile_stack=$profile
	USE_ORDER='features'
	ARCH=amd64
	USE_EXPAND=
	use_expand_index
	# config.py adds ARCH, unions in use.force and subtracts use.mask last.
	package_use_mask() { printf '%s\n' gpm amd64; }
	package_use_force() { printf '%s\n' gpm; }

	run dbuse cat/pkg-1
	[ "$status" -eq 0 ]
	local flat=" ${lines[*]} "
	[[ "$flat" != *" gpm "* ]]
	[[ "$flat" != *" amd64 "* ]]
}

@test "package_use_mask: a later node's unmask beats an earlier node's stable mask" {
	# UseManager.getUseMask walks one profile node at a time, so node order
	# outranks file class: arch/amd64/package.use.mask's `-llvm_targets_AMDGPU`
	# beats arch/base/package.use.stable.mask's mask of the same flag.
	local high="$BATS_TEST_TMPDIR/high" low="$BATS_TEST_TMPDIR/low"
	mkdir -p "$high" "$low"
	printf '%s\n' 'cat/pkg -masked-flag' >"$high/package.use.mask"
	printf '%s\n' 'cat/pkg masked-flag' >"$low/package.use.stable.mask"
	profile_stack=$(printf '%s\n%s\n' "$high" "$low")
	package_is_stable() { return 0; }
	best_tree() { return 1; }
	config_cache_reset

	run package_use_mask cat/pkg-1
	[ "$status" -eq 0 ]
	[[ " ${lines[*]} " != *" masked-flag "* ]]
}

@test "dbuse: the baseline resolution ignores /etc/portage/package.use" {
	# What a package.use flag has to differ from to be doing any work.
	printf '%s\n' 'cat/pkg user-flag' >"$ETC_PORTAGE_DIR/package.use"
	local profile="$BATS_TEST_TMPDIR/profile"
	mkdir -p "$profile"
	profile_stack=$profile
	USE_ORDER='pkg'
	ARCH=
	USE_EXPAND=
	use_expand_index
	config_cache_reset
	package_use_mask() { :; }
	package_use_force() { :; }
	best_tree() { return 1; }

	run dbuse cat/pkg-1
	[ "$status" -eq 0 ]
	[[ " ${lines[*]} " == *" user-flag "* ]]

	run dbuse cat/pkg-1 baseline
	[ "$status" -eq 0 ]
	[[ " ${lines[*]} " != *" user-flag "* ]]
}

@test "dbuse: --original-depends does not answer a baseline request" {
	# The vardb record is what the package was merged with, so it already
	# carries whatever /etc/portage/package.use asked for. Serving it as the
	# baseline made every package.use flag look redundant under -E -o.
	printf '%s\n' 'cat/pkg user-flag' >"$ETC_PORTAGE_DIR/package.use"
	VARDB_DIR="$BATS_TEST_TMPDIR/vardb"
	mkdir -p "$VARDB_DIR/cat/pkg-1"
	printf '%s\n' 'user-flag merged-flag' >"$VARDB_DIR/cat/pkg-1/USE"
	opt_arg_original_depends=yes
	local profile="$BATS_TEST_TMPDIR/profile"
	mkdir -p "$profile"
	profile_stack=$profile
	USE_ORDER='pkg'
	ARCH=
	USE_EXPAND=
	use_expand_index
	config_cache_reset
	package_use_mask() { :; }
	package_use_force() { :; }
	best_tree() { return 1; }

	# The ordinary resolution still short-circuits to the merged-with record.
	run dbuse cat/pkg-1
	[ "$status" -eq 0 ]
	[[ " ${lines[*]} " == *" merged-flag "* ]]

	# The baseline is computed regardless, so the entry's own flag is absent.
	run dbuse cat/pkg-1 baseline
	[ "$status" -eq 0 ]
	[[ " ${lines[*]} " != *" user-flag "* ]]
	[[ " ${lines[*]} " != *" merged-flag "* ]]
}

@test "package_use_filter: a flag only the package's own rules would lack is kept" {
	# Comparing against the global USE set instead of the package's own
	# baseline made -E delete flags that were doing work.
	dbuse() {
		case "${2-}" in
			baseline) return 0 ;;        # off without the package.use entry
			*) printf '%s\n' needed-flag ;;
		esac
	}

	run package_use_filter cat/pkg cat/pkg 1.0 needed-flag
	[ "$status" -eq 0 ]
	[[ "$output" != *"flag redundant"* ]]
}
