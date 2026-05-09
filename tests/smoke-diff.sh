#!/bin/bash
# Tolerance-aware diff for smoke snapshots.
#
# Filters volatile header lines (run timestamp, host kernel, cpv-resolution
# summary) from both sides before diffing. Other transient noise — line
# counts, sha256 markers, partial output for timed-out commands — is
# intentionally NOT filtered: those are the signals we want to surface when
# the parser changes shape.
#
# Usage:
#   tests/smoke-diff.sh BASELINE [SNAPSHOT]
#
# If SNAPSHOT is omitted, generates one fresh by running tests/smoke.sh
# against the current build (assumes ./src/dep is built).
#
# Exit codes:
#   0  no differences
#   1  differences found (diff prints to stdout)
#   2  invocation error (missing baseline, etc.)

set -u
HERE="$(cd "$(dirname "$0")" && pwd)"

if (( $# < 1 )); then
	echo "usage: $0 BASELINE [SNAPSHOT]" >&2
	exit 2
fi

baseline=$1
[[ -f "$baseline" ]] || {
	echo "baseline not found: $baseline" >&2
	exit 2
}

cleanup=()
trap '[[ ${#cleanup[@]} -gt 0 ]] && rm -f "${cleanup[@]}"' EXIT

if (( $# >= 2 )); then
	snapshot=$2
	[[ -f "$snapshot" ]] || {
		echo "snapshot not found: $snapshot" >&2
		exit 2
	}
else
	snapshot=$(mktemp -t udept-smoke.XXXXXX)
	cleanup+=("$snapshot")
	"$HERE/smoke.sh" >"$snapshot" || true
fi

# Filter:
#   - 'udept smoke harness — <ISO timestamp>'   (always changes per run)
#   - 'host: Linux <kernel> <arch>'             (kernel updates are unrelated)
#   - 'PORTAGE=... BASH=... PYTHON=...'         (cpv pins move with package
#                                               upgrades, not code changes)
# 'dep version: ...' is intentionally KEPT — a version bump is real signal.
filter='/^udept smoke harness /d; /^host: /d; /^PORTAGE=.*BASH=.*PYTHON=/d'

diff -u <(sed -E "$filter" "$baseline") <(sed -E "$filter" "$snapshot")
