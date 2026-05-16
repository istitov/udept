#!/usr/bin/env bats
# Smoke: virtual-package resolution.
#
# -R takes a bare cp (virtual/editor) and lists what providers are
# available. -r takes a cpv and lists what virtuals it provides.

load test_helper

setup() {
	require_dep_built
}

@test "smoke: -R virtuals/editor exits 0" {
	require_target VIRTUAL_EDITOR_CPV
	# Strip trailing -<version> so -R sees a bare cp.
	local cp="${VIRTUAL_EDITOR_CPV%-[0-9]*}"
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -R "$cp"
	assert_success
}

@test "smoke: -R virtuals/libc exits 0" {
	require_target VIRTUAL_LIBC_CPV
	local cp="${VIRTUAL_LIBC_CPV%-[0-9]*}"
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -R "$cp"
	assert_success
}

@test "smoke: -r provides/portage exits 0" {
	require_target PORTAGE_CPV
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -r "$PORTAGE_CPV"
	assert_success
}
