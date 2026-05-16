#!/usr/bin/env bats
# Smoke: virtual-package resolution.
#
# -R takes a bare cp (virtual/editor) and lists what providers are
# available. -r takes a cpv and lists what virtuals it provides.

load test_helper

setup() {
	require_dep_built
}

@test "smoke: -R virtuals/editor emits at least one provider" {
	require_target VIRTUAL_EDITOR_CPV
	# Strip trailing -<version> so -R sees a bare cp.
	local cp="${VIRTUAL_EDITOR_CPV%-[0-9]*}"
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -R "$cp"
	assert_success
	# virtual/editor must have at least one provider installed on any
	# system that has /var/db/pkg/virtual/editor-* in the first place.
	# '/' validates a cat/pkg row is present rather than just non-emptiness.
	[[ "$output" == */* ]]
}

@test "smoke: -R virtuals/libc emits at least one provider" {
	require_target VIRTUAL_LIBC_CPV
	local cp="${VIRTUAL_LIBC_CPV%-[0-9]*}"
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -R "$cp"
	assert_success
	# virtual/libc resolves to glibc/musl/uclibc — there's always
	# exactly one provider on a working system.
	[[ "$output" == */* ]]
}

@test "smoke: -r provides/portage exits 0" {
	require_target PORTAGE_CPV
	# portage doesn't itself satisfy any virtual on a normal install,
	# so output may be empty. Status-only check; the contract here is
	# 'dispatch path doesn't crash', not 'output is structured X'.
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -r "$PORTAGE_CPV"
	assert_success
}
