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

# Heuristic: warn when baseline and snapshot look like they came from
# different environments. The PORTAGE=... BASH=... PYTHON=... GLIBC=...
# line in the harness header lists dynamically-picked target cpvs;
# different hosts (different installed versions) and the dev-vs-CI split
# (host system vs. gentoo/stage3 container) make these diverge. When
# they do, the diff that follows will be dominated by cross-environment
# noise — every cpv reference, every contents listing, every revdep set
# differs — rather than real regressions. Print the mismatch up front
# so the noise is at least expected.
baseline_targets=$(sed -n '/^PORTAGE=/{p;q;}' "$baseline")
snapshot_targets=$(sed -n '/^PORTAGE=/{p;q;}' "$snapshot")
if [[ "$baseline_targets" != "$snapshot_targets" ]]; then
	{
		echo "Warning: baseline and snapshot have different resolved targets:"
		echo "  baseline: $baseline_targets"
		echo "  snapshot: $snapshot_targets"
		echo "Cross-environment diffs typically have many false positives —"
		echo "if you're comparing a CI baseline against a local snapshot,"
		echo "or vice versa, expect a lot of noise unrelated to any real change."
		echo
	} >&2
fi

# Filter:
#   - 'udept smoke harness — <ISO timestamp>'   (always changes per run)
#   - 'host: Linux <kernel> <arch>'             (kernel updates are unrelated)
#   - 'PORTAGE=... BASH=... PYTHON=...'         (cpv pins move with package
#                                               upgrades, not code changes)
# 'dep version: ...' is intentionally KEPT — a version bump is real signal.
filter='/^udept smoke harness /d; /^host: /d; /^PORTAGE=.*BASH=.*PYTHON=/d'

# --label gives the diff hunk headers ('--- BASELINE / +++ SNAPSHOT')
# meaningful paths instead of the /dev/fd/N that bash's process-substitution
# default produces.
diff -u --label "$baseline" --label "$snapshot" \
	<(sed -E "$filter" "$baseline") \
	<(sed -E "$filter" "$snapshot")
