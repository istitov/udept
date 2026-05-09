#!/usr/bin/env bats
# Unit tests for tests/smoke-diff.sh — the tolerance-aware diff helper
# used by 'make smoke-diff' and the CI baseline-comparison step.
#
# Verifies: filter strips volatile header lines (timestamp, host kernel,
# cpv-resolution summary); cross-environment diffs trigger a stderr
# warning; --label produces meaningful hunk paths; baseline / snapshot
# missing → exit 2; usage error → exit 2.

load 'test_helper'

setup() {
	SMOKE_DIFF="${BATS_TEST_DIRNAME}/../smoke-diff.sh"
	[[ -x "$SMOKE_DIFF" ]] || skip "smoke-diff.sh not found or not executable"
	BASELINE="$BATS_TEST_TMPDIR/baseline"
	SNAPSHOT="$BATS_TEST_TMPDIR/snapshot"
}

@test "smoke-diff: identical files → exit 0, no output" {
	cat >"$BASELINE" <<'EOF'
udept smoke harness — 2026-05-09T01:00:00Z
PORTAGE=foo BASH=bar PYTHON=baz
=== test ===
content line
EOF
	cp "$BASELINE" "$SNAPSHOT"
	run "$SMOKE_DIFF" "$BASELINE" "$SNAPSHOT"
	assert_success
	refute_output
}

@test "smoke-diff: only timestamp differs → exit 0 (filter strips it)" {
	cat >"$BASELINE" <<'EOF'
udept smoke harness — 2026-05-09T01:00:00Z
PORTAGE=foo BASH=bar PYTHON=baz
=== test ===
content
EOF
	cat >"$SNAPSHOT" <<'EOF'
udept smoke harness — 2026-05-10T02:34:56Z
PORTAGE=foo BASH=bar PYTHON=baz
=== test ===
content
EOF
	run "$SMOKE_DIFF" "$BASELINE" "$SNAPSHOT"
	assert_success
}

@test "smoke-diff: only host kernel differs → exit 0" {
	cat >"$BASELINE" <<'EOF'
host: Linux 7.0.0 x86_64
PORTAGE=foo BASH=bar PYTHON=baz
=== test ===
content
EOF
	cat >"$SNAPSHOT" <<'EOF'
host: Linux 7.1.5 x86_64
PORTAGE=foo BASH=bar PYTHON=baz
=== test ===
content
EOF
	run "$SMOKE_DIFF" "$BASELINE" "$SNAPSHOT"
	assert_success
}

@test "smoke-diff: real content change → exit 1, hunk in output" {
	cat >"$BASELINE" <<'EOF'
=== test ===
[exit=0 lines=1 sha=abc]
foo
EOF
	cat >"$SNAPSHOT" <<'EOF'
=== test ===
[exit=0 lines=1 sha=def]
bar
EOF
	run "$SMOKE_DIFF" "$BASELINE" "$SNAPSHOT"
	assert_failure
	assert_output --partial '@@ '
	assert_output --partial '-foo'
	assert_output --partial '+bar'
}

@test "smoke-diff: dep version line is signal, not noise" {
	# A 'dep version:' bump is a real change worth seeing — the filter
	# does NOT strip it, unlike the other header lines.
	cat >"$BASELINE" <<'EOF'
dep version: dep 0.6.0
PORTAGE=foo
=== test ===
content
EOF
	cat >"$SNAPSHOT" <<'EOF'
dep version: dep 0.7.0
PORTAGE=foo
=== test ===
content
EOF
	run "$SMOKE_DIFF" "$BASELINE" "$SNAPSHOT"
	assert_failure
	assert_output --partial '-dep version: dep 0.6.0'
	assert_output --partial '+dep version: dep 0.7.0'
}

@test "smoke-diff: missing baseline → exit 2, error to stderr" {
	: >"$SNAPSHOT"
	run "$SMOKE_DIFF" /nonexistent/baseline "$SNAPSHOT"
	assert_equal "$status" 2
	assert_output --partial 'baseline not found'
}

@test "smoke-diff: missing snapshot when given explicitly → exit 2" {
	: >"$BASELINE"
	run "$SMOKE_DIFF" "$BASELINE" /nonexistent/snapshot
	assert_equal "$status" 2
	assert_output --partial 'snapshot not found'
}

@test "smoke-diff: no args → exit 2 with usage" {
	run "$SMOKE_DIFF"
	assert_equal "$status" 2
	assert_output --partial 'usage:'
}

@test "smoke-diff: cross-environment PORTAGE → warning on stderr" {
	cat >"$BASELINE" <<'EOF'
PORTAGE=sys-apps/portage-3.0.78 BASH=app-shells/bash-5.3 PYTHON=dev-lang/python-3.13.0
=== test ===
content
EOF
	cat >"$SNAPSHOT" <<'EOF'
PORTAGE=sys-apps/portage-99.99.99 BASH=app-shells/bash-9.9 PYTHON=dev-lang/python-9.9
=== test ===
content
EOF
	run "$SMOKE_DIFF" "$BASELINE" "$SNAPSHOT"
	# 'run' captures stdout+stderr both into $output; the warning is on
	# stderr but lands here regardless.
	assert_output --partial 'different resolved targets'
	assert_output --partial 'Cross-environment diffs'
}

@test "smoke-diff: same PORTAGE → no warning" {
	cat >"$BASELINE" <<'EOF'
PORTAGE=sys-apps/portage-3.0.78 BASH=foo PYTHON=bar
=== test ===
content
EOF
	cp "$BASELINE" "$SNAPSHOT"
	run "$SMOKE_DIFF" "$BASELINE" "$SNAPSHOT"
	assert_success
	refute_output --partial 'different resolved targets'
}

@test "smoke-diff: --label produces meaningful hunk path headers (no /dev/fd/N)" {
	cat >"$BASELINE" <<'EOF'
=== test ===
foo
EOF
	cat >"$SNAPSHOT" <<'EOF'
=== test ===
bar
EOF
	run "$SMOKE_DIFF" "$BASELINE" "$SNAPSHOT"
	assert_failure
	assert_output --partial "--- $BASELINE"
	assert_output --partial "+++ $SNAPSHOT"
	refute_output --partial '/dev/fd/'
}
