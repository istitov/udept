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

# Helper: run crunch_depends on a tokenized input string. Bash's read
# inside crunch_depends consumes stdin one token per line, so callers
# heredoc multi-line input.
crunch() {
	# crunch_depends takes (cpv, ordeps) — cpv is passed to dbuse via
	# our mock so the value doesn't matter; ordeps controls ||-group
	# resolution mode.
	crunch_depends 'cat/test-1.0' "${1-}"
}

# ----- bare atoms -------------------------------------------------------

@test "crunch_depends: single bare atom passes through" {
	out=$(crunch <<'EOF'
cat/foo
EOF
)
	# Output is '<atom> <taint>'; trailing space when taint is empty.
	[[ "$out" == "cat/foo " ]]
}

@test "crunch_depends: multiple bare atoms each emit one line" {
	out=$(crunch <<'EOF'
cat/foo
cat/bar
cat/baz
EOF
)
	[[ "$(echo "$out" | wc -l)" -eq 3 ]]
	[[ "$out" == *"cat/foo"* ]]
	[[ "$out" == *"cat/bar"* ]]
	[[ "$out" == *"cat/baz"* ]]
}

@test "crunch_depends: blocker (!cat/pkg) passes through" {
	out=$(crunch <<'EOF'
!cat/blocker
EOF
)
	[[ "$out" == "!cat/blocker "* ]]
}

@test "crunch_depends: empty input → no output" {
	out=$(crunch </dev/null)
	[[ -z "$out" ]]
}

# ----- USE-conditionals -------------------------------------------------

@test "crunch_depends: 'flag?' gates inner atom when flag IS active" {
	FAKE_USE="myflag"
	out=$(crunch <<'EOF'
myflag?
cat/gated
EOF
)
	[[ "$out" == "cat/gated  myflag?"* ]]
}

@test "crunch_depends: 'flag?' discards inner atom when flag NOT active" {
	FAKE_USE="other"
	out=$(crunch <<'EOF'
myflag?
cat/gated
EOF
)
	[[ -z "$out" ]]
}

@test "crunch_depends: '!flag?' gates inner when flag NOT active" {
	FAKE_USE="other"
	out=$(crunch <<'EOF'
!myflag?
cat/gated
EOF
)
	[[ "$out" == "cat/gated  !myflag?"* ]]
}

@test "crunch_depends: '!flag?' discards when flag IS active" {
	FAKE_USE="myflag"
	out=$(crunch <<'EOF'
!myflag?
cat/gated
EOF
)
	[[ -z "$out" ]]
}

@test "crunch_depends: USE-conditional only gates ONE token (or one group)" {
	# 'flag?' followed by two atoms: only the first is gated.
	# Second atom is independent.
	FAKE_USE="other"  # myflag inactive → first atom dropped
	out=$(crunch <<'EOF'
myflag?
cat/gated
cat/independent
EOF
)
	[[ "$out" != *"gated"* ]]
	[[ "$out" == *"cat/independent"* ]]
}

@test "crunch_depends: nested USE-conditionals accumulate taint" {
	FAKE_USE="outer inner"
	out=$(crunch <<'EOF'
outer?
inner?
cat/deeply-gated
EOF
)
	# Both flags active → atom emitted with both in taint.
	[[ "$out" == *"cat/deeply-gated"* ]]
	[[ "$out" == *"outer?"* ]]
	[[ "$out" == *"inner?"* ]]
}

# ----- groups -----------------------------------------------------------

@test "crunch_depends: '( a b c )' evaluates each atom inside" {
	out=$(crunch <<'EOF'
(
cat/foo
cat/bar
)
EOF
)
	[[ "$out" == *"cat/foo"* ]]
	[[ "$out" == *"cat/bar"* ]]
}

@test "crunch_depends: 'flag? ( a b )' gates whole group" {
	FAKE_USE="myflag"
	out=$(crunch <<'EOF'
myflag?
(
cat/foo
cat/bar
)
EOF
)
	[[ "$out" == *"cat/foo"* ]]
	[[ "$out" == *"cat/bar"* ]]
	[[ "$out" == *"myflag?"* ]]
}

@test "crunch_depends: 'flag? ( a b )' drops whole group when flag inactive" {
	FAKE_USE=""
	out=$(crunch <<'EOF'
myflag?
(
cat/foo
cat/bar
)
EOF
)
	[[ -z "$out" ]]
}

@test "crunch_depends: nested groups recurse correctly" {
	out=$(crunch <<'EOF'
(
cat/outer
(
cat/inner
)
cat/sibling
)
EOF
)
	[[ "$out" == *"cat/outer"* ]]
	[[ "$out" == *"cat/inner"* ]]
	[[ "$out" == *"cat/sibling"* ]]
}

# ----- || groups (default mode: pick first satisfiable) ----------------

@test "crunch_depends: '|| ( a b )' picks first installed" {
	FAKE_INSTALLED="cat/b"
	FAKE_SATISFIABLE="cat/a cat/b"
	out=$(crunch <<'EOF'
||
(
cat/a
cat/b
)
EOF
)
	# 'cat/a' is satisfiable but only 'cat/b' is installed; default-mode
	# crunch_depends picks the installed one (cd_already_installed wins
	# over cd_satisfiable).
	[[ "$out" == *"cat/b"* ]]
	[[ "$out" != *"cat/a"* ]]
}

@test "crunch_depends: '|| ( a b )' falls back to first satisfiable when none installed" {
	FAKE_INSTALLED=""
	FAKE_SATISFIABLE="cat/b"  # only cat/b satisfiable
	out=$(crunch <<'EOF'
||
(
cat/a
cat/b
)
EOF
)
	[[ "$out" == *"cat/b"* ]]
}

@test "crunch_depends: '|| ( a b )' falls back to first listed when nothing matches" {
	FAKE_INSTALLED=""
	FAKE_SATISFIABLE=""
	out=$(crunch <<'EOF'
||
(
cat/a
cat/b
)
EOF
)
	# Neither installed nor satisfiable — fallback is the first listed.
	[[ "$out" == *"cat/a"* ]]
}

# ----- || groups (--with-or-deps=all and =safe modes) ------------------

@test "crunch_depends: ordeps=all → emit every alternative in '|| ( a b c )'" {
	FAKE_INSTALLED=""
	FAKE_SATISFIABLE="cat/a cat/b cat/c"
	out=$(crunch all <<'EOF'
||
(
cat/a
cat/b
cat/c
)
EOF
)
	[[ "$out" == *"cat/a"* ]]
	[[ "$out" == *"cat/b"* ]]
	[[ "$out" == *"cat/c"* ]]
}

@test "crunch_depends: ordeps=safe with single alternative → emit it" {
	out=$(crunch safe <<'EOF'
||
(
cat/only
)
EOF
)
	[[ "$out" == *"cat/only"* ]]
}

@test "crunch_depends: ordeps=safe with exactly-one-installed → emit only that" {
	FAKE_INSTALLED="cat/b"
	out=$(crunch safe <<'EOF'
||
(
cat/a
cat/b
cat/c
)
EOF
)
	[[ "$out" == *"cat/b"* ]]
	[[ "$out" != *"cat/a"* ]]
	[[ "$out" != *"cat/c"* ]]
}

@test "crunch_depends: ordeps=safe with multiple-installed → emit nothing (ambiguous)" {
	FAKE_INSTALLED="cat/a cat/b"
	out=$(crunch safe <<'EOF'
||
(
cat/a
cat/b
)
EOF
)
	# Ambiguous → safe mode declines to pick.
	[[ -z "$out" ]]
}

@test "crunch_depends: ordeps=safe with none-installed and >1 alternative → emit nothing" {
	FAKE_INSTALLED=""
	out=$(crunch safe <<'EOF'
||
(
cat/a
cat/b
)
EOF
)
	[[ -z "$out" ]]
}

# ----- combined ---------------------------------------------------------

@test "crunch_depends: USE-conditional wraps an ||-group" {
	FAKE_USE="myflag"
	FAKE_INSTALLED="cat/b"
	FAKE_SATISFIABLE="cat/a cat/b"
	out=$(crunch <<'EOF'
myflag?
(
||
(
cat/a
cat/b
)
)
EOF
)
	# Group is gated by myflag (active), || picks installed cat/b,
	# and the resulting atom carries 'myflag?' in its taint.
	[[ "$out" == *"cat/b"* ]]
	[[ "$out" == *"myflag?"* ]]
}

@test "crunch_depends: bare atoms after USE-conditional are unaffected" {
	FAKE_USE=""  # myflag inactive
	out=$(crunch <<'EOF'
myflag?
cat/gated
cat/free
cat/also-free
EOF
)
	[[ "$out" != *"gated"* ]]
	[[ "$out" == *"cat/free"* ]]
	[[ "$out" == *"cat/also-free"* ]]
}
