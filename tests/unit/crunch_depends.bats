#!/usr/bin/env bats
# Unit tests for crunch_depends — the DEPEND-string parser/evaluator.
# This is the most fragile part of dep.in: per its own comment block
# "If you think you can understand this code, you don't." Up to today
# it had zero direct unit coverage; bugs would manifest as wrong dep
# resolutions across the entire script and only show up via smoke or
# real-world breakage.
#
# Approach: stub the two underlying primitives the parser asks
# questions of — dbuse() (which USE flags are active for the cpv being
# crunched) and resolve_depatom() (is this atom installed / satisfiable
# in the live Portage tree). Both are heavyweight in production; mocking
# them lets us exercise the parser's branching logic in isolation.
#
# Input: pre-tokenized DEPEND text on stdin. raw_depends() does this
# tokenization at runtime — splits on whitespace, with parens promoted
# to standalone tokens. Tests feed the same shape via heredoc.
#
# Output: one '<atom> <taint>' line per surviving atom (after
# USE-conditional gating and ||-group resolution).
#
# Grammar (per dep.in:1697 ff.):
#   <depend-list> ::= <depend-node>*
#   <depend-node> ::= <b-atom> | <bracket-list> | <or-node> | <use-node>
#   <b-atom>      ::= <ATOM> | <blocker>
#   <blocker>     ::= "!"<ATOM>
#   <bracket-list>::= "(" <depend-list> ")"
#   <or-node>     ::= "||" "(" <depend-node>* ")"
#   <use-node>    ::= <use-selector>"?" <depend-node>
#   <use-selector>::= ["!"]<USE_FLAG>

load 'test_helper'

setup() {
	load_dep
	# Mocks for the two primitives crunch_depends calls into.
	# FAKE_USE controls which USE flags dbuse reports active.
	# FAKE_INSTALLED / FAKE_SATISFIABLE drive resolve_depatom's
	# installed-only / satisfiable-anywhere paths respectively.
	# shellcheck disable=SC2317
	dbuse() { echo "$FAKE_USE"; }
	# shellcheck disable=SC2317
	resolve_depatom() {
		local atom="$1" inst_only="$2"
		# resolve_depatom returns the resolved cpv on success, empty
		# on failure. The callers (cd_already_installed / cd_satisfiable)
		# only check for non-empty.
		if [[ "$inst_only" == "yes" ]]; then
			[[ " $FAKE_INSTALLED " == *" $atom "* ]] && echo "$atom"
		else
			[[ " $FAKE_SATISFIABLE " == *" $atom "* ]] && echo "$atom"
		fi
	}
	FAKE_USE=""
	FAKE_INSTALLED=""
	FAKE_SATISFIABLE=""
}

# crunch_depends takes (cpv, ordeps) — cpv is passed to dbuse via our
# mock so the value doesn't matter; ordeps controls ||-group resolution
# mode. crunch_depends itself terminates with non-zero exit when
# cd_evaluate_single hits EOF, so 'run' (which captures status without
# tripping bats' set -e) is the right wrapper.
crunch() {
	crunch_depends 'cat/test-1.0' "${1-}"
}

# ----- bare atoms -------------------------------------------------------

@test "crunch_depends: single bare atom passes through" {
	run crunch <<'EOF'
cat/foo
EOF
	# Output is '<atom> <taint>'; trailing space when taint is empty.
	assert_equal "${#lines[@]}" 1
	assert_output 'cat/foo '
}

@test "crunch_depends: multiple bare atoms each emit one line in order" {
	run crunch <<'EOF'
cat/foo
cat/bar
cat/baz
EOF
	assert_equal "${#lines[@]}" 3
	assert_line --index 0 'cat/foo '
	assert_line --index 1 'cat/bar '
	assert_line --index 2 'cat/baz '
}

@test "crunch_depends: blocker (!cat/pkg) passes through unchanged" {
	run crunch <<'EOF'
!cat/blocker
EOF
	assert_equal "${#lines[@]}" 1
	assert_output '!cat/blocker '
}

@test "crunch_depends: constrained atoms remain opaque tokens" {
	run crunch <<'EOF'
!!>=cat/pkg-2.0:0/2=::testrepo[foo(-)?,bar=]
EOF
	assert_equal "${#lines[@]}" 1
	assert_output '!!>=cat/pkg-2.0:0/2=::testrepo[foo(-)?,bar=] '
}

@test "crunch_depends: empty input → no output" {
	run crunch </dev/null
	refute_output
}

# ----- USE-conditionals -------------------------------------------------

@test "crunch_depends: 'flag?' gates inner atom when flag IS active" {
	FAKE_USE="myflag"
	run crunch <<'EOF'
myflag?
cat/gated
EOF
	assert_equal "${#lines[@]}" 1
	# Output: '<atom> <taint>' where taint accumulates ' myflag?'
	assert_output --regexp '^cat/gated +myflag\?'
}

@test "crunch_depends: 'flag?' discards inner atom when flag NOT active" {
	FAKE_USE="other"
	run crunch <<'EOF'
myflag?
cat/gated
EOF
	refute_output
}

@test "crunch_depends: '!flag?' gates inner when flag NOT active" {
	FAKE_USE="other"
	run crunch <<'EOF'
!myflag?
cat/gated
EOF
	assert_equal "${#lines[@]}" 1
	assert_output --regexp '^cat/gated +!myflag\?'
}

@test "crunch_depends: '!flag?' discards when flag IS active" {
	FAKE_USE="myflag"
	run crunch <<'EOF'
!myflag?
cat/gated
EOF
	refute_output
}

@test "crunch_depends: USE-conditional only gates ONE token (or one group)" {
	# 'flag?' followed by two atoms: only the first is gated.
	# Second atom is independent.
	FAKE_USE="other"  # myflag inactive → first atom dropped
	run crunch <<'EOF'
myflag?
cat/gated
cat/independent
EOF
	assert_equal "${#lines[@]}" 1
	assert_output 'cat/independent '
	refute_output --partial 'cat/gated'
}

@test "crunch_depends: nested USE-conditionals accumulate taint" {
	FAKE_USE="outer inner"
	run crunch <<'EOF'
outer?
inner?
cat/deeply-gated
EOF
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'cat/deeply-gated'
	assert_output --partial 'outer?'
	assert_output --partial 'inner?'
}

# ----- groups -----------------------------------------------------------

@test "crunch_depends: '( a b c )' evaluates each atom inside" {
	run crunch <<'EOF'
(
cat/foo
cat/bar
)
EOF
	assert_equal "${#lines[@]}" 2
	assert_output --partial 'cat/foo'
	assert_output --partial 'cat/bar'
}

@test "crunch_depends: empty group '( )' emits nothing and doesn't crash" {
	# Defensive — ebuild authors don't write '( )' on purpose, but a
	# preprocessing bug or odd indirection could produce one.
	run crunch <<'EOF'
(
)
cat/sibling
EOF
	# Just the sibling, no spurious empty-group atoms.
	assert_equal "${#lines[@]}" 1
	assert_output 'cat/sibling '
}

@test "crunch_depends: 'flag? ( a b )' gates whole group" {
	FAKE_USE="myflag"
	run crunch <<'EOF'
myflag?
(
cat/foo
cat/bar
)
EOF
	assert_equal "${#lines[@]}" 2
	assert_output --partial 'cat/foo'
	assert_output --partial 'cat/bar'
	# Both rows carry myflag? in taint.
	[[ $(grep -c 'myflag?' <<<"$output") -eq 2 ]]
}

@test "crunch_depends: 'flag? ( a b )' drops whole group when flag inactive" {
	FAKE_USE=""
	run crunch <<'EOF'
myflag?
(
cat/foo
cat/bar
)
EOF
	refute_output
}

@test "crunch_depends: 'flag? ( a ( b ) c )' deeply skips when inactive" {
	# cd_discard_single's depth-tracking: must consume the inner group too,
	# not stop at the first ')' it sees. Without correct depth handling,
	# cat/sibling would be wrongly attached to the discarded group's
	# context and dropped.
	FAKE_USE=""
	run crunch <<'EOF'
myflag?
(
cat/a
(
cat/b
)
cat/c
)
cat/sibling
EOF
	assert_equal "${#lines[@]}" 1
	assert_output 'cat/sibling '
}

@test "crunch_depends: nested groups recurse correctly" {
	run crunch <<'EOF'
(
cat/outer
(
cat/inner
)
cat/sibling
)
EOF
	assert_equal "${#lines[@]}" 3
	assert_output --partial 'cat/outer'
	assert_output --partial 'cat/inner'
	assert_output --partial 'cat/sibling'
}

# ----- || groups (default mode: pick first satisfiable) ----------------

@test "crunch_depends: '|| ( a b )' picks first installed" {
	FAKE_INSTALLED="cat/b"
	FAKE_SATISFIABLE="cat/a cat/b"
	run crunch <<'EOF'
||
(
cat/a
cat/b
)
EOF
	# 'cat/a' is satisfiable but only 'cat/b' is installed; default-mode
	# crunch_depends picks the installed one (cd_already_installed wins
	# over cd_satisfiable). Exclusion check too: cat/a must NOT appear.
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'cat/b'
	refute_output --partial 'cat/a'
}

@test "crunch_depends: '|| ( a b )' falls back to first satisfiable when none installed" {
	FAKE_INSTALLED=""
	FAKE_SATISFIABLE="cat/b"  # only cat/b satisfiable
	run crunch <<'EOF'
||
(
cat/a
cat/b
)
EOF
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'cat/b'
	refute_output --partial 'cat/a'
}

@test "crunch_depends: '|| ( a b )' falls back to first listed when nothing matches" {
	FAKE_INSTALLED=""
	FAKE_SATISFIABLE=""
	run crunch <<'EOF'
||
(
cat/a
cat/b
)
EOF
	# Neither installed nor satisfiable — fallback is the first listed.
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'cat/a'
	refute_output --partial 'cat/b'
}

@test "crunch_depends: '|| ( ( a b ) ( c d ) )' picks first whole group" {
	# ||-of-groups: each group inside || is a single alternative; the
	# parser should select the first whole group (when nothing's installed
	# or satisfiable, default-mode picks first listed).
	FAKE_INSTALLED=""
	FAKE_SATISFIABLE=""
	run crunch <<'EOF'
||
(
(
cat/a
cat/b
)
(
cat/c
cat/d
)
)
EOF
	# First group emitted (cat/a + cat/b on one line because
	# cd_evaluate_single emits group atoms together as a single ||-arm).
	assert_output --partial 'cat/a'
	assert_output --partial 'cat/b'
	refute_output --partial 'cat/c'
	refute_output --partial 'cat/d'
}

@test "crunch_depends: '|| ( !cat/foo cat/bar )' handles blocker alternative" {
	# Blockers are valid in ||-groups — '|| ( !A B )' means "A must not
	# be installed OR B is satisfied". cd_already_installed strips the
	# leading '!' before resolve_depatom and inverts the test, so a
	# blocker resolves as 'installed' iff the named package is NOT
	# installed.
	FAKE_INSTALLED=""              # cat/foo NOT installed, so '!cat/foo' satisfied
	FAKE_SATISFIABLE="cat/bar"     # cat/bar satisfiable too
	run crunch <<'EOF'
||
(
!cat/foo
cat/bar
)
EOF
	# !cat/foo is "already installed" (its package isn't there → blocker
	# is satisfied) so it wins as the first installed alternative.
	assert_output --partial '!cat/foo'
	refute_output --partial 'cat/bar'
}

# ----- || groups (--with-or-deps=all and =safe modes) ------------------

@test "crunch_depends: ordeps=all → emit every alternative in '|| ( a b c )'" {
	FAKE_INSTALLED=""
	FAKE_SATISFIABLE="cat/a cat/b cat/c"
	run crunch all <<'EOF'
||
(
cat/a
cat/b
cat/c
)
EOF
	assert_equal "${#lines[@]}" 3
	assert_output --partial 'cat/a'
	assert_output --partial 'cat/b'
	assert_output --partial 'cat/c'
}

@test "crunch_depends: ordeps=safe with single alternative → emit it" {
	run crunch safe <<'EOF'
||
(
cat/only
)
EOF
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'cat/only'
}

@test "crunch_depends: ordeps=safe with exactly-one-installed → emit only that" {
	FAKE_INSTALLED="cat/b"
	run crunch safe <<'EOF'
||
(
cat/a
cat/b
cat/c
)
EOF
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'cat/b'
	refute_output --partial 'cat/a'
	refute_output --partial 'cat/c'
}

@test "crunch_depends: ordeps=safe with multiple-installed → emit nothing (ambiguous)" {
	FAKE_INSTALLED="cat/a cat/b"
	run crunch safe <<'EOF'
||
(
cat/a
cat/b
)
EOF
	# Ambiguous → safe mode declines to pick.
	refute_output
}

@test "crunch_depends: ordeps=safe with none-installed and >1 alternative → emit nothing" {
	FAKE_INSTALLED=""
	run crunch safe <<'EOF'
||
(
cat/a
cat/b
)
EOF
	refute_output
}

# ----- combined ---------------------------------------------------------

@test "crunch_depends: USE-conditional wraps an ||-group" {
	FAKE_USE="myflag"
	FAKE_INSTALLED="cat/b"
	FAKE_SATISFIABLE="cat/a cat/b"
	run crunch <<'EOF'
myflag?
(
||
(
cat/a
cat/b
)
)
EOF
	# Group is gated by myflag (active), || picks installed cat/b,
	# and the resulting atom carries 'myflag?' in its taint.
	assert_equal "${#lines[@]}" 1
	assert_output --partial 'cat/b'
	assert_output --partial 'myflag?'
	refute_output --partial 'cat/a'
}

@test "crunch_depends: bare atoms after USE-conditional are unaffected" {
	FAKE_USE=""  # myflag inactive
	run crunch <<'EOF'
myflag?
cat/gated
cat/free
cat/also-free
EOF
	# Only cat/free + cat/also-free emitted; cat/gated dropped.
	assert_equal "${#lines[@]}" 2
	assert_output --partial 'cat/free'
	assert_output --partial 'cat/also-free'
	refute_output --partial 'cat/gated'
}
