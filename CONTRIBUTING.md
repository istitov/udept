# Contributing to udept

Thanks for taking the time to look at udept. This file covers what
you need to know to file a bug, propose a feature, or send a pull
request.

## Reporting bugs

Open an issue using the **Bug report** template. It asks for:

- the exact `dep --version` output (matches `dep v. <ver> "<tag>"`)
- the portage / eix / portage-utils versions involved — udept parses
  output from all three; a tool format change is a common bug class
- the command you ran and the full output (paste raw, colour-stripped
  with `--colour=no` if a paste-friendly version would render with
  ANSI bracketing)
- what you expected to happen vs what actually happened
- if the bug involves a specific package's metadata, the contents of
  `/var/db/pkg/<cat>/<pkg>/{DEPEND,RDEPEND,IUSE,USE,SLOT,KEYWORDS}` —
  the bug-report template lists typical pairings

Reproducible reports get triaged first.

## Proposing features

Open an issue using the **Feature request** template. Describe the
use case before the proposed implementation — `dep` has dozens of
flags across action / info / option categories, and there's often a
way to do what you want already. Check `dep --help` and `man dep`
first.

## Submitting pull requests

Fork the repo, create a branch off `main`, open a PR. Two
requirements:

1. **Tests stay green.** Locally:

   ```sh
   autoreconf -i
   ./configure
   make
   make check           # bats unit suite (200 tests, all stubbed)
   make check-smoke     # bats smoke tier (41 tests, real Portage tree)
   ```

   `make check-smoke` needs a populated `/var/db/pkg` and the real
   eix/qatom/portageq binaries; per-test `require_target` skips
   gracefully when a target package isn't installed, so a fresh
   stage3 still works. Reverse-walk tests (-L, -T, -X, -wp, -Pp,
   depclean) accept exit 124 (timeout) alongside 0 — they scale
   with revdep count and can exceed any reasonable wall-clock cap
   on a populated maintainer system.

   And independently, the dist tarball must build cleanly in an
   isolated tree — verified by:

   ```sh
   make distcheck
   ```

   CI runs both bats tiers, `shellcheck --severity=error src/dep`,
   completion-file syntax checks (`bash -n` / `zsh -n`), and `make
   distcheck` on `gentoo/stage3:latest`. New code paths need at
   least one test.

2. **`shellcheck --severity=error src/dep` clean.** CI enforces this
   threshold; the local [`.shellcheckrc`](.shellcheckrc) honours the
   same baseline. Lower-severity findings are tracked for a future
   cleanup pass but don't block.

Two patterns in `src/dep.in` deliberately keep `# shellcheck
disable=...` directives:

- `SC2104` at `handle_arg_info`: `continue` propagates up to the
  caller's `for` loop (POSIX-defined behaviour); restructuring would
  obscure the option parser's dynamic-scoped state.
- `SC2151` across `comm_float` / `comm_ver`: negative-return-as-
  signed-magnitude (`return -- -1` truncates to 255 via bash's mod-256)
  is documented at the function header and load-bearing — `vercmp()`
  reads `$? >= 128` to mean "less than".

If you touch those areas, keep the directives and update the rationale
comment alongside any behaviour change.

## Smoke vs snapshot

The bats smoke tier (`tests/smoke/`) asserts exit status plus one
stable structural marker per dispatch path. It catches hard crashes
and dispatch-format collapse but not subtle output reordering. The
older shell harness (`tests/smoke.sh` + `tests/smoke-diff.sh` +
`tests/baseline.ci`) covers that gap via byte-diffable snapshots:

```sh
make smoke              # one-off snapshot to stdout
make smoke-baseline     # write snapshot to tests/baseline.local
make smoke-diff         # diff against tests/baseline.ci (or override)
```

Use the snapshot tier when investigating an output-format change.
CI runs only the bats tier.

## Source layout

`src/dep.in` is organised into 24 topical sections.  Each section is
introduced by a banner of the form:

```
# ============================================================================
# === SECTION NAME
# === Brief description.  Function list.
# ============================================================================
```

Run `make toc` from the project root to see the full section index with
line numbers.  When adding a function, drop it under the right existing
section (don't leave it floating between sections); when adding a whole
new topical area, copy an existing banner as the template and keep the
shape so `make toc` keeps working.

Almost every function has a one-line docstring of the form `# name:
brief description.` directly above its definition.  Add one for any new
function; keep the description ground-truth (echoes what it does, not
the call sites).  Functions with richer multi-line inline comments
(e.g. memoise, the comm_* version-compare primitives) keep those
instead — the docstring convention is the minimum, not the maximum.

## Adding a new flag

A new flag typically needs changes in several places:

- `src/dep.in` — the code, including arg parsing and `--help`
- `doc/depman.sh` — emits `dep.1` manpage entries; new option needs
  an entry under the matching section (action / info / general)
- `completion/dep.completion.in` and `completion/dep.zsh.in` — bash
  and zsh completion templates
- [`ChangeLog`](ChangeLog) — under the next release's entry
- `tests/unit/` and/or `tests/smoke/` — at least one coverage test

Removing a flag touches the same places.

## Commit messages

Substantive commits get a structured body explaining *why*, not just
*what* the diff shows. Subject line under 70 characters, imperative
mood, no trailing period. Pure cosmetic / typo commits can stay
single-line.

## Code style

- `dep.in` is bash 4+; no POSIX-shell pretensions. Uses `local -a`,
  `[[ ]]`, `(( ))`, parameter expansion freely. The script is sourced
  into tests via `load_dep` in `tests/unit/test_helper.bash`.
- Tab indentation throughout (see [`.editorconfig`](.editorconfig)).
- External tool calls: `dep` shells out to `portageq` and `emerge`
  only — no `eix` / `qatom` / `equery` dependency. If a new code path
  needs a portage-utils helper, prefer reading `/var/db/pkg/<cpv>/*`
  or `metadata/md5-cache/<cpv>` directly when feasible (most of dep's
  existing reads do).
- For sed substitutions interpolating user-controlled values, escape
  the pattern. Raw interpolation of cpvs or USE strings into `s|||`
  is the canonical footgun shape — wrap in a helper that quotes the
  regex metacharacters first.

## Signing

`main` commits are GPG-signed. PRs don't need to be signed by the
contributor; signing happens at merge time. Work on a feature branch
named `modernization-*` can stay unsigned during iteration.

## License

By contributing you agree that your changes are licensed under
GPL-3.0-or-later (the project's license; see [`COPYING`](COPYING)).
