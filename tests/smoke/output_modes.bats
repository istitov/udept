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

@test "smoke: --colour=html -i wraps output in balanced HTML tags" {
	require_target PORTAGE_CPV
	# --colour=no first, --colour=html second; last wins per dep's
	# parser. Verifies the colorize machinery's HTML branch.
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no --colour=html -i "$PORTAGE_CPV"
	assert_success
	# HTML mode emits <span class="..."> wrappers around colored
	# segments. The literal '<span' substring catches the case where
	# the HTML branch is suppressed entirely.
	assert_output --partial '<span'
	# Tag balance: every opened <span...> must have a matching </span>.
	# Catches a regression that emits half-rendered tags (e.g.
	# truncated colorize output, or a missing close-tag handler) —
	# the partial-match above would pass on that broken state.
	# Counting via grep -o then wc -l; grep -c counts MATCHING LINES
	# not matches, which would undercount when multiple tags appear
	# on the same line.
	local n_open n_close
	n_open=$(printf '%s\n' "$output" | grep -oE '<span[[:space:]]' | wc -l)
	n_close=$(printf '%s\n' "$output" | grep -oE '</span>' | wc -l)
	if (( n_open != n_close )); then
		printf 'unbalanced <span> tags: open=%d close=%d\n' \
			"$n_open" "$n_close" >&2
		return 1
	fi
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
