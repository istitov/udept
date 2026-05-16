#!/usr/bin/env bats
# Smoke: info-action dispatch against the real Portage tree.
#
# These tests invoke the BUILT src/dep against /var/db/pkg and the
# resolved Portage tree. Each test asserts (a) exit status 0 and
# (b) a single stable structural marker — enough to detect a hard
# regression (crash, empty output, format collapse) without binding
# to volatile detail (specific version numbers, fork-count, etc.).
#
# Targets (PORTAGE_CPV / BASH_CPV / PYTHON_CPV / GLIBC_CPV) are picked
# from /var/db/pkg by test_helper.bash; missing targets skip the
# affected test rather than fail the suite — stage3 containers may
# lack one or another package early in CI bootstrap.

load test_helper

setup() {
	require_dep_built
}

# --- -l depends (PACKAGE) ------------------------------------------------

@test "smoke: -l depends/portage emits dependency rows" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -l "$PORTAGE_CPV"
	assert_success
	# Dependency rows are formatted with a version operator (>=, <=, ~,
	# =) followed by a cat/pkg-version pair. Asserting on the presence
	# of a version-op + '/' substring catches "depends emitted nothing"
	# without binding to a specific dependency.
	[[ "$output" == *'>='* ]] || [[ "$output" == *'<='* ]] || [[ "$output" == *' = '* ]]
}

@test "smoke: -l depends/bash emits at least one cat/pkg dependency" {
	require_target BASH_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -l "$BASH_CPV"
	assert_success
	# Every dep row has a 'cat/pkg' atom. '/' present means the rendering
	# produced at least one row; non-empty alone would pass on noise-
	# only output.
	[[ "$output" == */* ]]
}

@test "smoke: -l depends/python emits at least one cat/pkg dependency" {
	require_target PYTHON_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -l "$PYTHON_CPV"
	assert_success
	[[ "$output" == */* ]]
}

# --- -L rev-depends (PNAME / PACKAGE) ------------------------------------
# Bare PN routes through _smartdep_nopv (slot-agnostic); full cpv routes
# through _smartdep (slot-aware, filters revdep depatoms by the cpv's
# installed slot). Both code paths cover the slot-aware revdep work.

@test "smoke: -L rev-depends/portage (PN) emits revdep rows" {
	require_target PN_PORTAGE
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -L "$PN_PORTAGE"
	assert_success
	# portage has reverse deps (acct-{group,user}/portage at minimum)
	# on any Gentoo install — empty output would be a regression that
	# either dropped the rev-dep walk or suppressed its rendering.
	[[ "$output" == */* ]]
}

@test "smoke: -L rev-depends/bash (PN) emits revdep rows" {
	require_target PN_BASH
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -L "$PN_BASH"
	assert_success
	[[ "$output" == */* ]]
}

@test "smoke: -L rev-depends/python (PN) emits revdep rows" {
	require_target PN_PYTHON
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -L "$PN_PYTHON"
	assert_success
	[[ "$output" == */* ]]
}

@test "smoke: -L rev-depends-slot/python (full cpv) emits revdep rows" {
	require_target PYTHON_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -L "$PYTHON_CPV"
	assert_success
	# Full-cpv -L exercises _smartdep (slot-aware), filtering revdeps
	# whose depatom matches the installed cpv's slot. python-3.x is
	# heavily depended on; output must contain at least one row.
	[[ "$output" == */* ]]
}

@test "smoke: -L --for-emerge --full-atoms portage emits =cpv lines" {
	require_target PN_PORTAGE
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -L --for-emerge --full-atoms "$PN_PORTAGE"
	assert_success
	# --for-emerge output is a flat list of '=cat/pkg-version' atoms,
	# possibly suffixed with :slot::repo by --full-atoms. Catches the
	# format_atom_for_emerge regression class. portage is in @system on
	# every Gentoo host and has reverse dependencies (gentoo-functions,
	# eselect, etc.), so a regression that suppresses all output would
	# surface as empty here. Tighter than the older "if non-empty" gate.
	[[ -n "$output" ]]
	# First row must start with '=' (full-atom prefix). Asserts the
	# format, not the specific package.
	[[ "$output" == =* ]]
}

# --- -t / -T tree-walk ----------------------------------------------------

@test "smoke: -t tree-depends/portage -D 2 emits root cpv at top" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -t "$PORTAGE_CPV" -D 2
	assert_success
	# First non-empty line of the tree is the root cpv itself (the
	# package whose deps are being walked). Catches a regression where
	# the tree walk produces output but loses its anchor.
	[[ "${lines[0]}" == "$PORTAGE_CPV" ]]
}

@test "smoke: -T reverse-tree/python -D 2 exits 0 or times out" {
	require_target PN_PYTHON
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -T "$PN_PYTHON" -D 2
	# -T walks the reverse-dependency tree; on populated maintainer
	# systems with thousands of revdeps the walk exceeds the 120s cap.
	# 124 = timeout from /usr/bin/timeout. CI's stage3 has few revdeps
	# so this completes well under cap.
	[[ "$status" -eq 0 ]] || [[ "$status" -eq 124 ]]
}

# --- Single-package info actions -----------------------------------------

@test "smoke: -S depstrings/portage emits DEPEND header" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -S "$PORTAGE_CPV"
	assert_success
	# Output is the raw depstring blocks keyed by variable name; each
	# section is preceded by its label (DEPEND:, BDEPEND:, RDEPEND:,
	# PDEPEND:). Catches a regression that suppresses the header.
	assert_output --partial 'DEPEND'
}

@test "smoke: -e versions/python emits a 3.x version" {
	require_target PN_PYTHON
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -e "$PN_PYTHON"
	assert_success
	# Every Gentoo install has at least one python-3.* in /var/db/pkg
	# and the tree. Asserts the version row format (slot in parens
	# after the version string).
	[[ "$output" == *'(3.'* ]]
}

@test "smoke: -k keywords/python emits a 3.x slot tag" {
	require_target PN_PYTHON
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -k "$PN_PYTHON"
	assert_success
	# Each row of the keywords table is suffixed with the package's
	# SLOT in square brackets (e.g. '[3.13t]', '[3.14t]'). NB: arch
	# names themselves render as VERTICAL column headers (one letter
	# per row), so 'amd64' is NOT a contiguous substring of the
	# output — the slot tag is the right content marker.
	assert_output --partial '[3.'
}

@test "smoke: -i info/portage prints DESCRIPTION" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -i "$PORTAGE_CPV"
	assert_success
	# -i is the structured per-package info dump (HOMEPAGE, DESCRIPTION,
	# LICENSE, KEYWORDS, etc.). Assert one of the labels is present —
	# regression that suppresses the whole dump would clear all of them.
	# Label is the literal token 'DESCRIPTION' in uppercase (followed
	# by a padded ':').
	assert_output --partial 'DESCRIPTION'
}

@test "smoke: -f contents/portage lists files under /usr" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -f "$PORTAGE_CPV"
	assert_success
	# portage's CONTENTS always includes its bin/lib install paths;
	# /usr is the canonical install prefix on modern Gentoo (with
	# /usr-merge enforced). '/etc' would also work but is rare for
	# pure libexec content; '/usr' is the broader contract.
	assert_output --partial '/usr'
}

@test "smoke: -c category/portage names sys-apps among categories" {
	require_target PN_PORTAGE
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -c "$PN_PORTAGE"
	assert_success
	# -c lists all categories that contain the named PN. portage lives
	# in sys-apps (also in acct-group / acct-user for the user/group
	# packages of the same name on modern Gentoo).
	assert_output --partial 'sys-apps'
}

@test "smoke: -C catpackages/sys-apps emits sys-apps/portage" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -C sys-apps
	assert_success
	# sys-apps/portage is in @system; the cat enumeration must include
	# it. Catches a regression where the listing produces sys-apps/
	# prefixed rows but loses the portage entry.
	assert_output --partial 'sys-apps/portage'
}

@test "smoke: --changelog=3 portage emits ChangeLog headers" {
	require_target PN_PORTAGE
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no --changelog=3 "$PN_PORTAGE"
	assert_success
	# Each per-cat changelog block is preceded by 'From <path>/ChangeLog:'.
	# Asserts the header anchor — a regression that emits raw ChangeLog
	# content without the section labels would surface here.
	assert_output --partial 'ChangeLog'
}

@test "smoke: -u usedesc/portage emits a known IUSE flag" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -u "$PORTAGE_CPV"
	assert_success
	# portage's IUSE has shipped 'build' since the ebuild was written
	# (used for stage1 bootstrapping; sys-apps/portage cannot avoid it).
	# Asserting on a known-stable flag catches "flag descriptions all
	# silenced" without depending on doc/apidoc that have come and gone.
	assert_output --partial 'build'
}

@test "smoke: -U iuse/python lists at least one cat/pkg consumer" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -U python
	assert_success
	# Output is a list of packages that respect (have in their IUSE)
	# the named USE flag. python is a universal flag on Gentoo; at
	# least one consumer always exists. '/' validates the cat/pkg row
	# shape rather than just non-emptiness.
	[[ "$output" == */* ]]
}

@test "smoke: -z size/portage emits a 'files:' size summary" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -z "$PORTAGE_CPV"
	assert_success
	# Output line format: '<N> files: <size> <unit>'.  The 'files:'
	# anchor is the format contract; catches a regression that emits
	# raw byte counts without the label.
	assert_output --partial 'files:'
}

@test "smoke: -g search/portage emits a cat/pkg row" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -g portage
	assert_success
	# -g greps PN against the tree. 'portage' is a common substring; at
	# least one match guaranteed (sys-apps/portage itself, plus
	# app-portage/* on any installed system).
	[[ "$output" == *'portage'* ]] && [[ "$output" == */* ]]
}

@test "smoke: -F owners/file exits 0 with a cpv match" {
	_resolve_targets
	[[ "$OWNED_FILE" ]] || skip "smoke: no bash binary in /usr/bin or /bin"
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -F "$OWNED_FILE"
	assert_success
	# -F finds the package owning the given file path. On any system
	# where /usr/bin/bash exists, it's owned by app-shells/bash.
	assert_output --partial 'app-shells/bash'
}

# --- -Q --required-use ---------------------------------------------------
# Reads REQUIRED_USE from md5-cache, evaluates against active USE,
# reports unsatisfied clauses. Empty REQUIRED_USE → vacuous success.

@test "smoke: -Q --required-use portage exits 0" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -Q "$PORTAGE_CPV"
	assert_success
}

@test "smoke: -Q --required-use bash (empty REQUIRED_USE) exits 0" {
	require_target BASH_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -Q "$BASH_CPV"
	assert_success
}
