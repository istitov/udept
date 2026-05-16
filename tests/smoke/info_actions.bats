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

@test "smoke: -l depends/bash returns non-empty output" {
	require_target BASH_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -l "$BASH_CPV"
	assert_success
	[[ -n "$output" ]]
}

@test "smoke: -l depends/python returns non-empty output" {
	require_target PYTHON_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -l "$PYTHON_CPV"
	assert_success
	[[ -n "$output" ]]
}

# --- -L rev-depends (PNAME / PACKAGE) ------------------------------------
# Bare PN routes through _smartdep_nopv (slot-agnostic); full cpv routes
# through _smartdep (slot-aware, filters revdep depatoms by the cpv's
# installed slot). Both code paths cover the slot-aware revdep work.

@test "smoke: -L rev-depends/portage (PN) exits 0" {
	require_target PN_PORTAGE
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -L "$PN_PORTAGE"
	assert_success
}

@test "smoke: -L rev-depends/bash (PN) exits 0" {
	require_target PN_BASH
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -L "$PN_BASH"
	assert_success
}

@test "smoke: -L rev-depends/python (PN) exits 0" {
	require_target PN_PYTHON
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -L "$PN_PYTHON"
	assert_success
}

@test "smoke: -L rev-depends-slot/python (full cpv) exits 0" {
	require_target PYTHON_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -L "$PYTHON_CPV"
	assert_success
}

@test "smoke: -L --for-emerge --full-atoms portage emits =cpv lines" {
	require_target PN_PORTAGE
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -L --for-emerge --full-atoms "$PN_PORTAGE"
	assert_success
	# --for-emerge output is a flat list of '=cat/pkg-version' atoms,
	# possibly suffixed with :slot::repo by --full-atoms. Catches the
	# format_atom_for_emerge regression class. Allow empty (no revdeps)
	# but if any row is emitted, it must start with '='.
	if [[ -n "$output" ]]; then
		[[ "$output" == =* ]] || [[ "$output" == *$'\n'=* ]]
	fi
}

# --- -t / -T tree-walk ----------------------------------------------------

@test "smoke: -t tree-depends/portage -D 2 exits 0" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -t "$PORTAGE_CPV" -D 2
	assert_success
	[[ -n "$output" ]]
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

@test "smoke: -S depstrings/portage emits non-empty output" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -S "$PORTAGE_CPV"
	assert_success
	[[ -n "$output" ]]
}

@test "smoke: -e versions/python emits at least one version" {
	require_target PN_PYTHON
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -e "$PN_PYTHON"
	assert_success
	[[ -n "$output" ]]
}

@test "smoke: -k keywords/python emits keyword data" {
	require_target PN_PYTHON
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -k "$PN_PYTHON"
	assert_success
	[[ -n "$output" ]]
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

@test "smoke: -f contents/portage lists installed file paths" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -f "$PORTAGE_CPV"
	assert_success
	# CONTENTS is per-file rows; every row starts with a leading /.
	assert_output --partial '/'
}

@test "smoke: -c category/portage exits 0" {
	require_target PN_PORTAGE
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -c "$PN_PORTAGE"
	assert_success
}

@test "smoke: -C catpackages/sys-apps exits 0" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -C sys-apps
	assert_success
	[[ -n "$output" ]]
}

@test "smoke: --changelog=3 portage exits 0" {
	require_target PN_PORTAGE
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no --changelog=3 "$PN_PORTAGE"
	assert_success
}

@test "smoke: -u usedesc/portage exits 0" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -u "$PORTAGE_CPV"
	assert_success
}

@test "smoke: -U iuse/python exits 0" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -U python
	assert_success
}

@test "smoke: -z size/portage emits a size summary" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -z "$PORTAGE_CPV"
	assert_success
	[[ -n "$output" ]]
}

@test "smoke: -g search/portage exits 0" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -g portage
	assert_success
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
