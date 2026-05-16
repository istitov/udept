#!/usr/bin/env bats
# Smoke: help / version / usage dispatch — no Portage tree required.
#
# Catches:
#   - @PACKAGE_VERSION@ substitution failure (literal token in --version)
#   - Early-init crash before argv dispatch
#   - Help-text regression (one of the action/info option blocks dropped)
#   - --version / --usage / --help argument-stripping logic breakage

load test_helper

setup() {
	require_dep_built
}

@test "smoke: --usage exits 0 with banner" {
	run "$DEP_BIN" --colour=no --usage
	assert_success
	assert_output --partial 'Usage: dep'
}

@test "smoke: --version exits 0 and reports a version string" {
	run "$DEP_BIN" --colour=no --version
	assert_success
	# The version banner is 'dep v. <version> "<tag>"'. Asserting on the
	# 'dep v.' prefix catches @PACKAGE_VERSION@ substitution failure
	# (would leave the literal token in place) without hardcoding the
	# specific version number — the test survives bumps.
	assert_output --partial 'dep v.'
}

@test "smoke: --help exits 0 and lists info actions" {
	run "$DEP_BIN" --colour=no --help
	assert_success
	# --help dumps the full action + info table. Asserting on a stable
	# action name ('depends') catches the case where the table dump
	# regresses silently to empty.
	assert_output --partial 'depends'
}
