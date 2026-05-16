#!/usr/bin/env bats
# Smoke: -x / -X existence probes.
#
# -x: does PACKAGE depend (transitively) on PNAME? (exit 0 yes / 1 no)
# -X: does PNAME have any reverse dependent matching a later PACKAGE?
#
# Exit code is the assertion of interest — either 0 or 1 is acceptable
# depending on what's installed; what we're guarding against is hard
# crash (non-zero non-one exit, panic stderr).

load test_helper

setup() {
	require_dep_built
}

@test "smoke: -x exists portage:bash returns 0 or 1" {
	require_target PORTAGE_CPV
	require_target PN_BASH
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -x "$PORTAGE_CPV" "$PN_BASH"
	# 0 = exists, 1 = not exists. Any other status is a regression.
	[[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

@test "smoke: -X rev-exists python:bash returns 0, 1, or times out" {
	require_target PN_PYTHON
	require_target PN_BASH
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -X "$PN_PYTHON" "$PN_BASH"
	# 0 = exists, 1 = not exists. 124 = timeout (from /usr/bin/timeout)
	# is also accepted: -X walks the full reverse-dep graph and can
	# exceed any reasonable cap on a populated maintainer system. On
	# CI's stage3 container it completes well under 120s.
	[[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]] || [[ "$status" -eq 124 ]]
}
