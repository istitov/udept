#!/usr/bin/env bats
# Unit tests for format_revdep — the stdin-driven formatter that
# produces revdep output rows from '_smartdep' / '_smartdep_nopv' tuples
# of '<deppkg> <depatom> <taint>'. Branches:
#
#   - regular cpv → cpv + taint + depatom row
#   - WORLD sentinel → 'WORLD FILE' label + depatom
#   - SYSTEM sentinel → 'SYSTEM PROFILE' label + depatom
#   - KERNEL sentinel → 'RUNNING KERNEL' (depatom suppressed)
#   - --for-emerge mode → flat 'format_atom_for_emerge' output, sentinels skipped
#
# The format_* helpers (cpv / depatom / taint / cpv padding) have their
# own concerns; we stub them so tests assert format_revdep's structure
# rather than re-cover their formatting choices.
#
# format_revdep returns $ndeps (the row count it processed) as its
# exit status — not 0/1 success/fail. We use bats's 'run' wrapper which
# captures the exit status into $status without tripping bats's
# default 'set -e'.

load 'test_helper'

setup() {
	load_dep
	# Disable colour so output is plain ASCII for assertions.
	NO= GR= RD= BR= BL= YL= CY= FC= Gr= Bl= Rd=
	opt_arg_for_emerge=
	opt_arg_full_atoms=
	# Stub the format helpers — keep input visible, drop padding/colour.
	format_cpv()      { printf '%s' "$1"; }
	format_depatom()  { printf '%s' "$1"; [[ "$2" ]] && printf ' [asvirt=%s]' "$2"; }
	format_taint()    { :; }  # taint formatting is decorative
	format_atom_for_emerge() { printf '=%s\n' "$1"; }  # mirrors real default
	pad()             { printf '%s' "$2"; }
	pads()            { :; }
}

@test "format_revdep: truly empty stdin (no lines) → no output, returns 0" {
	# '<<<""' is a one-empty-line here-string, which read still consumes;
	# '</dev/null' is the only way to feed zero lines.
	run format_revdep </dev/null
	assert_success
	refute_output
}

@test "format_revdep: single regular cpv triple → row contains cpv + depatom" {
	run format_revdep <<<"cat/pkg-1.0 dev-libs/foo bar?"
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'cat/pkg-1.0'
	assert_output --partial 'dev-libs/foo'
}

@test "format_revdep: returns ndeps as exit code" {
	run format_revdep <<EOF
cat/a-1.0 dev-libs/foo
cat/b-1.0 dev-libs/foo
cat/c-1.0 dev-libs/foo
EOF
	assert_equal "$status" 3
	assert_equal "${#lines[@]}" 3
}

@test "format_revdep: WORLD sentinel → exactly one 'WORLD FILE' row" {
	run format_revdep <<<"WORLD dev-libs/foo"
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'WORLD FILE'
	assert_output --partial 'dev-libs/foo'
	refute_output --partial 'PROFILE'
	refute_output --partial 'KERNEL'
}

@test "format_revdep: SYSTEM sentinel → exactly one 'SYSTEM PROFILE' row" {
	run format_revdep <<<"SYSTEM dev-libs/foo"
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'SYSTEM PROFILE'
	assert_output --partial 'dev-libs/foo'
	refute_output --partial 'WORLD FILE'
	refute_output --partial 'KERNEL'
}

@test "format_revdep: KERNEL sentinel → 'RUNNING KERNEL' (no depatom column)" {
	run format_revdep <<<"KERNEL"
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'RUNNING KERNEL'
	# KERNEL emits no depatom — sentinel labels for the other two
	# absent because deppkg is exclusive.
	refute_output --partial 'FILE'
	refute_output --partial 'PROFILE'
}

@test "format_revdep: --for-emerge → flat '=cpv' output for regular rows" {
	opt_arg_for_emerge=1
	run format_revdep <<<"cat/pkg-1.0 dev-libs/foo bar?"
	# Note: $status reflects ndeps (1 here), not pass/fail — don't
	# assert_success.
	assert_output '=cat/pkg-1.0'
}

@test "format_revdep: --for-emerge skips WORLD sentinel" {
	opt_arg_for_emerge=1
	run format_revdep <<<"WORLD dev-libs/foo"
	refute_output
}

@test "format_revdep: --for-emerge skips SYSTEM sentinel" {
	opt_arg_for_emerge=1
	run format_revdep <<<"SYSTEM dev-libs/foo"
	refute_output
}

@test "format_revdep: --for-emerge skips KERNEL sentinel" {
	opt_arg_for_emerge=1
	run format_revdep <<<"KERNEL"
	refute_output
}

@test "format_revdep: --for-emerge mixed input → emits exactly the regular rows" {
	opt_arg_for_emerge=1
	run format_revdep <<EOF
cat/pkg-1.0 dev-libs/foo
WORLD dev-libs/foo
SYSTEM dev-libs/bar
cat/qux-2.0 dev-libs/foo
KERNEL
EOF
	# Two regular rows, three sentinels skipped → exactly 2 lines.
	assert_equal "${#lines[@]}" 2
	assert_output --partial '=cat/pkg-1.0'
	assert_output --partial '=cat/qux-2.0'
	refute_output --partial 'WORLD'
	refute_output --partial 'SYSTEM'
	refute_output --partial 'KERNEL'
}

@test "format_revdep: asvirtual arg threaded into format_depatom" {
	# Our setup() stub appends ' [asvirt=X]' when an asvirtual is passed.
	run format_revdep "virtual/foo" <<<"cat/pkg-1.0 dev-libs/bar"
	assert_output --partial 'asvirt=virtual/foo'
}

@test "format_revdep: indent argument used as row prefix" {
	run format_revdep "" "    " <<<"cat/pkg-1.0 dev-libs/foo"
	# Row begins with the four-space indent (default is one tab).
	[[ "$output" == "    "* ]]
}

@test "format_revdep: blank input lines pass through without crashing" {
	# Defensive — a blank line shouldn't abort the whole format pass.
	run format_revdep <<EOF
cat/pkg-1.0 dev-libs/foo

EOF
	assert_output --partial 'cat/pkg-1.0'
}
