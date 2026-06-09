#!/usr/bin/env bats
# Smoke: action dispatch (--prune, --purge, --depclean, filter-etc,
# overlay-clean) — all read-only / pretend, no /etc/portage or
# /var/lib/portage mutation.
#
# `dep -dp` would shell out to emerge --pretend -C, whose runtime is
# dominated by emerge's own dep graph walk (5+ minutes on a populated
# system) — that's mostly a test of emerge, not dep. We drive the
# underlying redundant() helper directly via --exec instead; same code
# path through crunch_depends / _smartdep, but skips the emerge fork.
#
# These actions walk every installed cpv's deps; on a maintainer's
# full system that's thousands of packages and easily blows past any
# reasonable wall-clock cap. CI's stage3 container has a tiny package
# set so it completes fast. The shared smoke harness (smoke.sh) treats
# timeout as expected and embeds '[timed out after Ns]' in the
# snapshot rather than failing — we mirror that posture: accept 0
# (completed) or 124 (timeout from /usr/bin/timeout). A hard crash
# (non-zero non-124) is a real regression.

load test_helper

# Assert status is either 0 (completed) or 124 (timeout) — anything
# else is a hard crash and a real regression.
assert_completed_or_timed_out() {
	if [[ "$status" -ne 0 && "$status" -ne 124 ]]; then
		printf 'expected exit 0 or 124 (timeout), got %d\n--- output ---\n%s\n' \
			"$status" "$output" >&2
		return 1
	fi
}

setup() {
	require_dep_built
}

@test "smoke: -wp pruneworld --pretend exits 0 or times out" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -wp
	assert_completed_or_timed_out
}

@test "smoke: -Pp purge --pretend exits 0 or times out" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -Pp
	assert_completed_or_timed_out
}

@test "smoke: --exec redundant (depclean inner) exits 0 or times out" {
	# 300s cap matches smoke.sh's depclean override. stderr is the
	# parallel cp+mlsr line for human display; smoke discards it to
	# keep the assertion stable.
	run timeout 300 "$DEP_BIN" --colour=no --exec 'redundant 2>/dev/null'
	assert_completed_or_timed_out
}

@test "smoke: -E filter-etc-portage --ask=no --pretend exits 0" {
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -E --ask=no --pretend
	assert_success
}

@test "smoke: -O overlay-clean against a nonexistent path exits 0" {
	# Target dir doesn't exist; the action just prints what it would
	# do (or nothing). Exercises the early-return path.
	run timeout "$DEP_TIMEOUT" "$DEP_BIN" --colour=no -O /tmp/udept-nonexistent-overlay
	assert_success
}

@test "smoke: a SIGTERM'd action walker cleans up without leaking temp-dir errors" {
	# A long --pruneworld cut short by timeout(1) must exit on SIGTERM (its
	# TERM trap exits) instead of deleting temp_dir and then running on — the
	# latter let the rest of the walk + print_stats touch the just-removed
	# temp_dir, spewing 'No such file' / 'dep: line N:'. On a sparse host -wp
	# may finish inside the 3s window; either way there must be no such leak.
	run timeout 3 "$DEP_BIN" --colour=no -wp
	refute_output --partial 'No such file'
	refute_output --regexp 'line [0-9]+:'
}
