#!/usr/bin/env bats
# Regression test for extract_var's cache-source resolution.
#
# dep reads package metadata from md5-cache, not by sourcing ebuilds. Besides a
# repo's in-tree metadata/md5-cache, Portage also keeps a generated depcache
# under $EDB_DIR/dep/<abs-repo-path>/ — used for overlays that ship no in-tree
# cache (only profiles/ + metadata/layout.conf). extract_var used to read only
# the in-tree location, so every metadata read for such an overlay's
# uninstalled packages failed loudly (`!!! failed extract_var ...`), breaking
# -O / -e / -S / -l / -k on those overlays. The fix adds the depcache as a
# fallback; both locations share the key=value md5-cache format.

load 'test_helper'

setup() {
	load_dep
	# Keep the vardb fallback away from the real /var/db/pkg.
	VARDB_DIR="$BATS_TEST_TMPDIR/vardb"; mkdir -p "$VARDB_DIR"
	tree="$BATS_TEST_TMPDIR/repo"
}

@test "extract_var: reads SLOT from \$EDB_DIR/dep when the overlay has no in-tree md5-cache" {
	mkdir -p "$tree/cat/pkg"                       # overlay dir, NO metadata/md5-cache
	EDB_DIR="$BATS_TEST_TMPDIR/edb"
	mkdir -p "$EDB_DIR/dep$tree/cat"
	printf 'EAPI=8\nKEYWORDS=~amd64\nSLOT=3\n' >"$EDB_DIR/dep$tree/cat/pkg-1.0"

	run extract_var SLOT cat/pkg-1.0 "$tree"
	assert_success
	assert_output '3'
}

@test "extract_var: in-tree md5-cache takes precedence over \$EDB_DIR/dep" {
	mkdir -p "$tree/metadata/md5-cache/cat"
	printf 'SLOT=intree\n' >"$tree/metadata/md5-cache/cat/pkg-1.0"
	EDB_DIR="$BATS_TEST_TMPDIR/edb"
	mkdir -p "$EDB_DIR/dep$tree/cat"
	printf 'SLOT=edb\n' >"$EDB_DIR/dep$tree/cat/pkg-1.0"

	run extract_var SLOT cat/pkg-1.0 "$tree"
	assert_success
	assert_output 'intree'
}

@test "extract_var: no cache in either location -> clean failure (return 1)" {
	mkdir -p "$tree/cat/pkg"
	EDB_DIR="$BATS_TEST_TMPDIR/edb"; mkdir -p "$EDB_DIR"   # depcache dir, but no entry

	run extract_var SLOT cat/pkg-1.0 "$tree"
	assert_failure
	assert_output --partial 'failed extract_var'
}
