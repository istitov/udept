# Property-invariant tier for udept's config-mutating actions.
#
# Scope: the two actions that rewrite on-disk Portage config —
#   dep -E  (filter-etc-portage : prune redundant entries from
#            package.use / package.mask / package.unmask /
#            package.accept_keywords / package.keywords / profile/packages
#            / bashrc, preserving comments)
#   dep -w  (pruneworld         : drop redundant entries from the world file)
#
# WHY a separate tier from tests/unit:
#   The unit tier sources dep.in and exercises filter_etc_file / filter_world
#   in isolation, but it STUBS the per-file filter callbacks (a local
#   `myfilter`) and asserts golden output. The bug class these mutating
#   actions actually shipped (0.7.4: ask_install_new_file's `exit 0` aborting
#   the filter_etc_portage walk; a trailing comment block dropped at EOF) is
#   precisely what stubbing the real filter + pinning the expected text hides:
#   it lives in the interaction between the REAL metadata-driven filters and
#   the file walk. This tier drives the real filter_etc_portage / filter_world
#   end-to-end over synthetic fixtures and asserts ORACLE-FREE invariants that
#   hold WITHOUT predicting the host-specific output:
#     * idempotence            — apply twice; the second run is a no-op
#     * inventory-preservation — the atom set after is a SUBSET of before
#                                (these actions only ever remove entries)
#     * no-duplicate           — no line gains a repeated flag/keyword base
#     * comment-preservation   — on a fixture where nothing is removed, every
#                                comment line survives byte-for-byte
#   A non-idempotent, atom-inventing, flag-duplicating, or comment-dropping
#   rewrite fails these by construction — no golden file to maintain.
#
# WHY this sources the script instead of running the built `src/dep`:
#   udept's paths are hard globals relocatable only as a unit via EROOT, and
#   resolve_eroot_paths + read_repos_config resolve metadata through the
#   host's portageq AGAINST that EROOT. So a built-binary run cannot point the
#   WRITE target at a sandbox while keeping package metadata on the real tree —
#   it is all-or-nothing under one root. Sourcing (the same idiom tests/unit
#   uses via load_dep) lets us override ONLY the write targets
#   (ETC_PORTAGE_DIR / WORLD_FILE) and leave VARDB/repos resolution on the real
#   host, read-only. The functions are identical to the built `dep` (the build
#   only substitutes @PACKAGE_VERSION@/@PACKAGE_TAG@). main()/arg-parsing is
#   covered against the live tree by the smoke tier; this tier covers the
#   filters' transform invariants. install_new_file writes directly (no
#   doas/sudo) when the target is writable, so force-mode apply against a
#   user-owned sandbox needs no privilege escalation.
#
# Fixtures are SYNTHETIC and anonymous: fake cat-test/* atoms, generic flag
# tokens, and ~testarch keywords that match no real ACCEPT_KEYWORDS. A real
# package appears ONLY where the redundancy filter genuinely needs tree
# metadata, and then only a universal @system one (sys-apps/grep) plus an
# obviously-fake flag — see tests/property/*.bats.

# Reuse the unit tier's bats-support/bats-assert discovery and its careful
# load_dep (trap save/restore around the source). BATS_TEST_DIRNAME is the
# running .bats file's dir (tests/property), so this resolves to
# tests/unit/test_helper.bash, and load_dep's own ../../src/dep.in resolves to
# the repo's src/dep.in from here too.
load "${BATS_TEST_DIRNAME}/../unit/test_helper"

# Run a dep function with errexit off (dep.in is not written for `set -e`;
# the unit tier wraps calls the same way). Used for the filters, whose only
# effects we care about are on disk.
prop_run_unguarded() {
	( set +e; "$@" )
}

# Populate the Portage config arrays the filters consult (profile USE, masks,
# USE_EXPAND, ...) exactly as main() does — but in THIS shell, so the arrays
# persist for the filter calls. errexit-guarded because load_portage_config
# uses ((...)) patterns that abort under set -e.
prop_load_config() {
	local _e=; [[ $- == *e* ]] && _e=1
	set +e
	load_portage_config
	[[ $_e ]] && set -e
	return 0
}

# Create a writable sandbox and point ONLY the write targets at it; leave
# VARDB_DIR / repos resolution at their real-host defaults (read-only). The
# scratch temp_dir is DISTINCT from the targets — filter_etc_file writes its
# candidate to $temp_dir/<name> before ask_install_new_file installs it, and a
# temp_dir == target would self-truncate (the suspect-the-harness lesson).
prop_sandbox() {
	PROP_ROOT="$(mktemp -d)"
	PROP_ETC="$PROP_ROOT/etc/portage"
	PROP_LIB="$PROP_ROOT/var/lib/portage"
	mkdir -p "$PROP_ETC" "$PROP_LIB"
	ETC_PORTAGE_DIR="$PROP_ETC"
	WORLD_FILE="$PROP_LIB/world"
	WORLD_SETS_FILE="$PROP_LIB/world_sets"
	ETC_PORTAGE_SETS_DIR="$PROP_ETC/sets"
	temp_dir="$(mktemp -d)"
	do_action=force          # apply without prompting
}

# Standard per-test bring-up: source dep.in, build the sandbox, load real
# Portage config. Call from a test's setup().
prop_setup() {
	load_dep
	prop_sandbox
	prop_load_config
}

# Apply a mutating action ($1 = filter_etc_portage | filter_world) against the
# sandbox, swallowing its stdout/stderr (kept entries are tee'd to stdout, the
# REDUNDANT-entry log goes to stderr).
prop_apply() {
	prop_run_unguarded "$1" >/dev/null 2>&1
}

# --- oracle-free assertions ------------------------------------------------

# The set of package atoms (first whitespace field of every non-comment,
# non-blank line) in a file, sorted-unique.
atoms_of() {
	awk 'NF && $1 !~ /^#/ { print $1 }' "$1" | sort -u
}

# Idempotence: snapshot the whole sandbox tree, apply $1 once more, and assert
# the tree is byte-identical. Call AFTER a first prop_apply has settled it.
assert_idempotent() {
	local action="$1" snap
	snap="$(mktemp -d)"
	cp -a "$PROP_ROOT/." "$snap/"
	prop_apply "$action"
	run diff -r "$snap" "$PROP_ROOT"
	assert_success
}

# Inventory-preservation: every atom present in $2 (after) must have been
# present in $1 (before). These actions only remove, never invent. comm -13
# prints lines unique to the second input; it must be empty.
assert_atoms_subset() {
	run comm -13 <(atoms_of "$1") <(atoms_of "$2")
	assert_output ''
}

# No-duplicate: within any single entry line, no flag/keyword base token (the
# field with a leading - or ~ stripped) appears twice. Inline comments are
# stripped first; the atom in field 1 is not a flag.
assert_no_dup_flags() {
	run awk '
		/^[[:space:]]*#/ { next }
		{ sub(/[[:space:]]*#.*/, "") }
		NF < 2 { next }
		{
			delete seen
			for (i = 2; i <= NF; i++) {
				b = $i; sub(/^[-~]+/, "", b)
				if (b in seen) { print FILENAME ":" FNR ": duplicate \"" b "\""; bad = 1 }
				seen[b] = 1
			}
		}
		END { exit bad ? 1 : 0 }
	' "$1"
	assert_success
}

# Comment-preservation: assert the file at $PROP_ETC/$2 is byte-identical
# after applying $1. Use ONLY on fixtures where no entry is removed (a removed
# entry legitimately takes its attached comment block with it) — i.e. pure
# comment files, or entries the host cannot find redundant.
assert_apply_preserves_file() {
	local action="$1" rel="$2" before
	before="$(mktemp)"
	cp -a "$PROP_ETC/$rel" "$before"
	prop_apply "$action"
	run diff "$before" "$PROP_ETC/$rel"
	assert_success
}
