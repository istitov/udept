#!/usr/bin/env bats
# Smoke: output-mode probes (--colour=html / --colour=auto).
#
# Bumps in dep's parser semantics treat the LAST --colour= flag on the
# command line as winning. test_helper.bash builds invocations that
# pass --colour=no first; these tests pass --colour=<mode> afterwards
# so the mode they name is the one actually exercised. Without that
# trick the --colour=no in shared scaffolding would override.

load test_helper

setup() {
	require_dep_built
}

@test "smoke: --colour=html -i wraps output in HTML tags" {
	require_target PORTAGE_CPV
	# --colour=no first, --colour=html second; last wins per dep's
	# parser. Verifies the colorize machinery's HTML branch.
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no --colour=html -i "$PORTAGE_CPV"
	assert_success
	# HTML mode emits <span class="..."> wrappers around colored
	# segments. Asserting on the literal '<span' substring catches a
	# regression that suppresses the HTML branch entirely.
	assert_output --partial '<span'
}

@test "smoke: --colour=auto under pipe matches --colour=no (no ANSI)" {
	require_target PORTAGE_CPV
	# Under a non-tty pipe (bats's `run`), auto-detect must emit no
	# ANSI escape sequences. Catches regressions where 'auto' starts
	# emitting colour codes when stdout is redirected.
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no --colour=auto -i "$PORTAGE_CPV"
	assert_success
	# ESC [ ... m is the SGR (colour) escape sequence. Output must
	# contain none under non-tty 'auto'.
	! printf '%s' "$output" | grep -q $'\x1b\\['
}
