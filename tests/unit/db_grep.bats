#!/usr/bin/env bats
# Unit tests for db_grep — scan installed-package metadata for a needle.
#
# Three branches:
#   --original-depends   find -name "$attr" -exec grep -l
#   --uninstalled        md5-cache full-record grep
#   default              vardb attribute-named-file grep ($attr selects
#                        the file: *DEPEND expands to the 5-name set,
#                        any other literal value matches that vardb
#                        attribute file)
#
# Regression: the default branch previously hardcoded the *DEPEND set
# and ignored $attr.  info_action_iuse calls db_grep with attr=IUSE
# and a follow-up `has $1 $(extract_var IUSE …)` filter — the filter
# eliminates false positives but the hardcoded *DEPEND scope produced
# false negatives for packages whose USE flag affects build/configure
# but not deps.  These tests pin attr-honouring behaviour.

load 'test_helper'

setup() {
	load_dep
	VARDB_DIR="$BATS_TEST_TMPDIR/vardb"
	mkdir -p "$VARDB_DIR"
	# Ensure default branch fires (not original-depends / uninstalled).
	opt_arg_original_depends=
	opt_arg_uninstalled=
}

# fake_install cat/pkg-VER FILE CONTENT [FILE CONTENT ...]
# Create the vardb dir and drop one attribute file per pair of args.
fake_install() {
	local cpv=$1; shift
	mkdir -p "$VARDB_DIR/$cpv"
	while [[ $# -ge 2 ]]; do
		printf '%s\n' "$2" >"$VARDB_DIR/$cpv/$1"
		shift 2
	done
}

@test "db_grep: attr=IUSE finds packages with needle in IUSE (default branch)" {
	fake_install 'cat/has-it-1.0'   IUSE  'foo bar baz'   DEPEND ''
	fake_install 'cat/has-it-2.0'   IUSE  'baz'           DEPEND ''
	fake_install 'cat/lacks-it-1.0' IUSE  'unrelated'     DEPEND ''
	result="$(db_grep '\<baz\>' '' IUSE | sort)"
	assert_equal "$result" "$(printf 'cat/has-it-1.0\ncat/has-it-2.0')"
}

@test "db_grep: attr=IUSE doesn't find needle that lives only in DEPEND" {
	# The exact failure mode the previous default branch (hardcoded
	# *DEPEND scope) produced: a USE flag mentioned in IUSE-affecting
	# build but never in a conditional dep would have been *missed*;
	# the old code would have *spuriously matched* the dep-only case.
	fake_install 'cat/iuse-only-1.0'   IUSE 'gtk-doc'   DEPEND ''
	fake_install 'cat/dep-only-1.0'    IUSE ''          DEPEND 'app-text/gtk-doc'
	result="$(db_grep '\<gtk-doc\>' '' IUSE | sort)"
	assert_equal "$result" "cat/iuse-only-1.0"
}

@test "db_grep: attr=*DEPEND expands to the 5-name dep set" {
	fake_install 'cat/in-depend-1.0'   DEPEND   'dep-foo/bar'
	fake_install 'cat/in-rdepend-1.0'  RDEPEND  'dep-foo/bar'
	fake_install 'cat/in-bdepend-1.0'  BDEPEND  'dep-foo/bar'
	fake_install 'cat/in-idepend-1.0'  IDEPEND  'dep-foo/bar'
	fake_install 'cat/in-pdepend-1.0'  PDEPEND  'dep-foo/bar'
	# Only IUSE — must NOT match.
	fake_install 'cat/in-iuse-only-1.0' IUSE    'dep-foo/bar'
	result="$(db_grep 'dep-foo/bar' '' '*DEPEND' | sort)"
	assert_equal "$result" "$(printf 'cat/in-bdepend-1.0\ncat/in-depend-1.0\ncat/in-idepend-1.0\ncat/in-pdepend-1.0\ncat/in-rdepend-1.0')"
}

@test "db_grep: empty attr (legacy two-arg call) defaults to *DEPEND expansion" {
	# Backwards compat for any caller that left $attr unset; behaviour
	# should be identical to attr='*DEPEND'.
	fake_install 'cat/has-dep-1.0'  RDEPEND  'sys-apps/grep'
	fake_install 'cat/no-dep-1.0'   IUSE     'sys-apps/grep'
	result="$(db_grep 'sys-apps/grep' '' '' | sort)"
	assert_equal "$result" "cat/has-dep-1.0"
}

@test "db_grep: attr=KEYWORDS finds packages with needle in KEYWORDS" {
	fake_install 'cat/stable-pkg-1.0'  KEYWORDS  'amd64 arm64'
	fake_install 'cat/x86-only-1.0'    KEYWORDS  'x86'
	# Word-boundary regex matches every '...amd64' token including '~amd64'
	# — that's just how \< / \> work — so use a needle that only appears
	# in one fixture.
	result="$(db_grep '\<arm64\>' '' KEYWORDS | sort)"
	assert_equal "$result" "cat/stable-pkg-1.0"
}
