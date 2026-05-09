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

# Helper: format_revdep returns $ndeps (line count) as its exit status,
# which is non-zero whenever the input has any rows. Under bats' default
# 'set -e' that aborts the test before assertions can run. fmt_run wraps
# the call so we capture stdout into $out and exit code into $rc without
# tripping errexit. Same workaround pattern as required_use.bats.
fmt_run() {
	set +e
	out=$("$@")
	rc=$?
	set -e
}

@test "format_revdep: truly empty stdin (no lines) → no output, returns 0" {
	# '<<<""' is a one-empty-line here-string, which read still consumes;
	# '</dev/null' is the only way to feed zero lines.
	fmt_run format_revdep </dev/null
	[[ $rc -eq 0 ]]
	[[ -z "$out" ]]
}

@test "format_revdep: single regular cpv triple → row contains cpv + depatom" {
	fmt_run format_revdep <<<"cat/pkg-1.0 dev-libs/foo bar?"
	[[ "$out" == *"cat/pkg-1.0"* ]]
	[[ "$out" == *"dev-libs/foo"* ]]
}

@test "format_revdep: returns ndeps as exit code" {
	fmt_run format_revdep <<EOF
cat/a-1.0 dev-libs/foo
cat/b-1.0 dev-libs/foo
cat/c-1.0 dev-libs/foo
EOF
	[[ $rc -eq 3 ]]
}

@test "format_revdep: WORLD sentinel → 'WORLD FILE' label" {
	fmt_run format_revdep <<<"WORLD dev-libs/foo"
	[[ "$out" == *"WORLD FILE"* ]]
	[[ "$out" == *"dev-libs/foo"* ]]
}

@test "format_revdep: SYSTEM sentinel → 'SYSTEM PROFILE' label" {
	fmt_run format_revdep <<<"SYSTEM dev-libs/foo"
	[[ "$out" == *"SYSTEM PROFILE"* ]]
	[[ "$out" == *"dev-libs/foo"* ]]
}

@test "format_revdep: KERNEL sentinel → 'RUNNING KERNEL' (no depatom column)" {
	fmt_run format_revdep <<<"KERNEL"
	[[ "$out" == *"RUNNING KERNEL"* ]]
	# No 'dev-libs/foo'-style depatom — KERNEL rows have nothing to show.
	[[ "$out" != *"FILE"* ]]
	[[ "$out" != *"PROFILE"* ]]
}

@test "format_revdep: --for-emerge → flat '=cpv' output for regular rows" {
	opt_arg_for_emerge=1
	fmt_run format_revdep <<<"cat/pkg-1.0 dev-libs/foo bar?"
	[[ "$out" == "=cat/pkg-1.0" ]]
}

@test "format_revdep: --for-emerge skips WORLD sentinel" {
	opt_arg_for_emerge=1
	fmt_run format_revdep <<<"WORLD dev-libs/foo"
	[[ -z "$out" ]]
}

@test "format_revdep: --for-emerge skips SYSTEM sentinel" {
	opt_arg_for_emerge=1
	fmt_run format_revdep <<<"SYSTEM dev-libs/foo"
	[[ -z "$out" ]]
}

@test "format_revdep: --for-emerge skips KERNEL sentinel" {
	opt_arg_for_emerge=1
	fmt_run format_revdep <<<"KERNEL"
	[[ -z "$out" ]]
}

@test "format_revdep: --for-emerge mixed input → emits only regular rows" {
	opt_arg_for_emerge=1
	fmt_run format_revdep <<EOF
cat/pkg-1.0 dev-libs/foo
WORLD dev-libs/foo
SYSTEM dev-libs/bar
cat/qux-2.0 dev-libs/foo
KERNEL
EOF
	# Two regular rows, three sentinels skipped.
	[[ "$out" == *"=cat/pkg-1.0"* ]]
	[[ "$out" == *"=cat/qux-2.0"* ]]
	[[ "$out" != *WORLD* ]]
	[[ "$out" != *SYSTEM* ]]
	[[ "$out" != *KERNEL* ]]
	# Two output lines, one '=...' per regular row.
	[[ $(echo "$out" | grep -c '^=') -eq 2 ]]
}

@test "format_revdep: asvirtual arg threaded into format_depatom" {
	# Our setup() stub appends ' [asvirt=X]' when an asvirtual is passed.
	fmt_run format_revdep "virtual/foo" <<<"cat/pkg-1.0 dev-libs/bar"
	[[ "$out" == *"asvirt=virtual/foo"* ]]
}

@test "format_revdep: indent argument used as row prefix" {
	fmt_run format_revdep "" "    " <<<"cat/pkg-1.0 dev-libs/foo"
	[[ "$out" == "    "* ]]  # four-space indent at start of row
}

@test "format_revdep: blank input lines don't crash" {
	# Defensive — a blank line shouldn't abort the whole format pass.
	fmt_run format_revdep <<EOF
cat/pkg-1.0 dev-libs/foo

EOF
	[[ "$out" == *"cat/pkg-1.0"* ]]
}
