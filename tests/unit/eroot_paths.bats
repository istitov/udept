#!/usr/bin/env bats

load 'test_helper'

setup() {
	load_dep
}

@test "explicit EROOT is honored without consulting host portageq" {
	local called="$BATS_TEST_TMPDIR/called"
	portageq() { printf called >"$called"; printf "EPREFIX=''\nEROOT='/'\n"; }
	EROOT="$BATS_TEST_TMPDIR/root/"
	EPREFIX=''
	PORTAGE_CONFIGROOT=''
	resolve_eroot_paths
	assert_equal "$VARDB_DIR" "$BATS_TEST_TMPDIR/root/var/db/pkg"
	assert_equal "$WORLD_FILE" "$BATS_TEST_TMPDIR/root/var/lib/portage/world"
	assert [ ! -e "$called" ]
}

@test "PORTAGE_CONFIGROOT and EPREFIX locate etc/portage configuration" {
	EROOT="$BATS_TEST_TMPDIR/root"
	EPREFIX='/prefix'
	PORTAGE_CONFIGROOT="$BATS_TEST_TMPDIR/config-root"
	resolve_eroot_paths
	assert_equal "$ETC_PORTAGE_DIR" "$BATS_TEST_TMPDIR/config-root/prefix/etc/portage"
}

@test "standalone PORTAGE_CONFIGROOT relocates etc/portage" {
	EROOT=''
	EPREFIX=''
	PORTAGE_CONFIGROOT="$BATS_TEST_TMPDIR/config-root"
	resolve_eroot_paths
	assert_equal "$ETC_PORTAGE_DIR" "$BATS_TEST_TMPDIR/config-root/etc/portage"
	assert_equal "$VARDB_DIR" "/var/db/pkg"
}

@test "relative roots are rejected" {
	local variable
	for variable in EROOT EPREFIX PORTAGE_CONFIGROOT; do
		EROOT=''
		EPREFIX=''
		PORTAGE_CONFIGROOT=''
		printf -v "$variable" '%s' 'relative/root'
		run resolve_eroot_paths
		assert_failure
		assert_output --partial '!!!'
		assert_output --partial "$variable must be absolute"
	done
}
