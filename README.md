# udept

[![CI](https://github.com/istitov/udept/actions/workflows/ci.yml/badge.svg)](https://github.com/istitov/udept/actions/workflows/ci.yml)
[![Latest release](https://img.shields.io/github/v/release/istitov/udept?display_name=tag&sort=semver)](https://github.com/istitov/udept/releases/latest)

A Gentoo Portage analysis toolkit, written in bash.

It ships a single program — `dep` — that reads Portage's on-disk databases
directly and answers questions about installed and available packages: what
depends on what, what is unused, what virtuals resolve to, what's masked,
which file came from which package, and so on. It can also clean the
`world` file, drop redundant entries from `/etc/portage`, and identify
unused ebuilds in an overlay.

`dep` is its own minimal Portage engine. It does not import the Python
`portage` module; it reads the vardb, the metadata cache, profiles, and
`/etc/portage` itself, and shells out to `portageq` only for environment
resolution.

## Niche: bash-only

Most Portage tooling lives in Python (`emerge`, `equery` /
`gentoolkit`, `pquery` / `pkgcore`) or C++ (`eix`). udept is an oddity
— a Portage analysis engine that is itself a single ~5000-line bash
script.

The trade-offs:

- No Python interpreter startup; commands fit naturally inside shell
  pipelines, and `dep --exec '...'` runs arbitrary bash inside the
  already-loaded engine. The whole tool is one file you can `bash -x`,
  hand-patch in place, or read end to end.
- The runtime dependency surface is small: bash, coreutils, and
  `portageq` (which ships with Portage anyway). No Python venv, no
  compiled extension, no separate cache database.
- Graph-walking actions (`-d`, `-s`, full `-T` across the installed
  set) are slower than they would be in Python or in a compiled
  language. This is the cost of the niche.
- When Portage's on-disk layout drifts, the breakage shows up here
  before it does in higher-level tools — the 0.6.0 release is what
  catching up looks like.

For fast high-level package queries, reach for `equery` or `eix`.
udept earns its place when you want a small, hackable, shell-native
lens on the same data.

## Status

Originally written by Ed Catmur in 2005–2006. Upstream has been dormant
for ~20 years and Portage internals have moved on considerably. The
**0.6.0** release (2026) is a modernization pass — based on the
[init-6/udept](https://gitlab.com/init-6/udept) GitLab repository —
that brings the tool back in line with current Portage:

- reads repository configuration from `/etc/portage/repos.conf`;
- reads ebuild metadata from `metadata/md5-cache` (no more `/var/cache/edb/dep`
  regen via `ebuild.sh`);
- understands modern atom syntax — slot dependencies, sub-slots,
  USE-dependencies, IUSE prefix characters (`+`, `-`);
- handles `BDEPEND` / `IDEPEND` alongside `DEPEND` / `RDEPEND` / `PDEPEND`;
- resolves virtuals against the `virtual/*` package category (the old
  `PROVIDE`-based model is gone);
- understands the modern overlay layout (Manifest2, `metadata/layout.conf`)
  for `--overlay-clean`;
- expands `world` sets (`@<set>` entries in `/var/lib/portage/world_sets`
  and `/etc/portage/sets/`);
- uses `portageq envvar -v` for safe environment resolution instead of an
  in-script `make.conf` shell-lexer;
- supports Gentoo Prefix / non-`/` `EROOT` installs.

The 0.6.0 work was carried out with heavy use of the Claude
large-language model (Anthropic) as a coding assistant; every change
was reviewed by hand and validated against a smoke-test harness before
landing.

The **0.7.0** release (2026) builds on the modernization:

- slot-aware reverse-dependency filtering — `dep -L cat/pkg-version`
  filters revdeps to those satisfied by the package's installed
  slot; `dep -L cat/pkg` (without a version) stays slot-agnostic;
- a new `--required-use` (`-Q`) info action that reads `REQUIRED_USE`
  from the md5-cache, evaluates against active USE, and reports
  any unsatisfied clauses;
- a `--full-atoms` flag that, paired with `--for-emerge`, appends
  `:slot::repo` to emitted atoms;
- a native zsh completion alongside the bash one;
- a 200-test bats unit suite (`make check`) and a smoke-harness
  regression net (`make smoke` / `make smoke-diff`) with stage3
  baseline diffing in CI.

The 0.7.0 work, like 0.6.0, was carried out with heavy use of the
Claude large-language model (Anthropic) as a coding assistant; every
change was reviewed by hand and validated against the bats unit
suite and the smoke-harness regression net before landing.

The **0.7.1** release (2026) is a fix + infrastructure point release.
The audit pass driven by shellcheck cleanup surfaced three real
bugs that had been silently broken: a case-shadow that left two of
six USE-resolution tiers as dead code (`pkginternal_use_for` was
unreachable; `env.d`'s profile.env extraction never fired), a
`comm_ver` typo that returned `1.2_alpha1 == 1.2.0_beta2` as equal,
and a `local foo=$(...) || return` pattern that silently swallowed
`virtual_version` failures. Test infrastructure expanded with a
bats smoke tier (`make check-smoke`, 41 tests against a real
Portage tree) and per-bug-fix unit tests (200 → 231). `src/dep` is
shellcheck-clean at both `--severity=error` and `--severity=warning`.
Two more `comm_ver` bugs (rc-suffix mis-ordering, `1.0` vs `1.0-r0`
aborting) surfaced during the test-pinning pass and are deferred to
0.7.2; see `ChangeLog` for details.

The 0.7.1 work used Claude (Anthropic) as a coding assistant on the
same review-by-hand basis as 0.7.0 / 0.6.0.

The **0.7.2** release (2026) fixes the two `comm_ver` bugs deferred
from 0.7.1: rc-suffix releases are now correctly ordered between
`_pre` and the release proper (the length-based status-class formula
was replaced with an explicit case statement), and `1.0` vs `1.0-r0`
no longer aborts the script (an equality check now handles the
case where both revisions normalise to empty). 236 unit tests
(5 new) pin both fixes. AI-assist disclosure as for 0.7.1.

The **0.7.3** release (2026), "Truth in Advertising", is a twin patch
release with portconf 2.0.1. Its headline fix is a mis-scoped vardb
scan: `db_grep`'s default branch ignored its `$attr` argument and
always scanned the `*DEPEND` file set, so `dep -U <flag>` (which expects
an IUSE-scoped scan) silently missed packages whose USE flag is in
`IUSE` but doesn't affect dependencies. A post-audit accuracy pass also
corrected 13 docstrings for factual drift (omissions, not inversions).
5 new `db_grep` unit tests. AI-assist disclosure as for 0.7.1.

The **0.7.4** release (2026), "Mind the EROOT", fixes four bugs in the
config-file apply pipeline (`dep -E` / `dep -w`), all variations on one
theme — honour the target environment rather than a hardcoded path or
the system root. `--pretend` no longer aborts the file walk at the
first changed file; the world file follows `$WORLD_FILE` / `EROOT`
instead of a hardcoded `/var/lib/portage/world`; a writable target is
written directly instead of needlessly escalating to doas/sudo; and a
dropped entry's comment no longer migrates onto the next kept line.
7 new unit tests (250 → 257) pin the fixes, and the three apply-path
fixes were additionally validated end-to-end against a writable
sandbox. AI-assist disclosure as for 0.7.1.

The **0.7.5** release (2026), "Same Difference", is a patch release —
more fixes from the per-flag shakeout, plus a property-invariant test
tier. `dep -j` no longer leaks a raw "No such file" for every package
on trees that ship no per-package ChangeLog; `-E` no longer drops a
trailing comment block or truncates a comments-only file (it defaults
to force, so that was real data loss); `extract_var` now falls back to
Portage's depcache under `$EDB_DIR/dep`, so overlays that ship no
in-tree md5-cache work (`dep -O` failed extracts on one such overlay
dropped 79 → 3); a SIGTERM mid-run exits cleanly instead of spamming
errors; and `dep -s` returns 0 when there is nothing to do. A new
property tier (`tests/property/`, `make check-properties`, 11 tests)
drives the real config-mutating filters over synthetic fixtures and
asserts idempotence, inventory-preservation, no duplicate flag, and
comment-preservation rather than golden output — the codename's
invariant. 8 new unit tests (257 → 265) pin the fixes. AI-assist
disclosure as for 0.7.1.

See `ChangeLog` for the full per-release history.

The **0.8.0** release (2026), "Trust, but Verify", hardens the places
where a read-only analysis error could become unsafe advice or a damaged
configuration. HTML output now passes through one escaping renderer;
dependency resolution uses one EAPI 8 matcher for versions, slots,
repositories, and USE dependencies; virtual and effective-USE evaluation
cover all visible ebuilds and active USE_ORDER components; explicit EROOT,
EPREFIX, and PORTAGE_CONFIGROOT values are authoritative; and CONTENTS
paths containing whitespace are parsed as fields rather than shell words.

Mutating actions are now dry-run by default. Use `--ask` for an interactive
apply or the new long-only `--force` for a non-interactive apply. File
replacement is same-directory and atomic, preserves metadata and valid
in-root symlinks, and rejects dangling or out-of-root symlinks. A Python
Portage differential suite is test-only: the Bash runtime remains
self-contained, while CI checks hundreds of real atom/candidate decisions
against Portage itself.

## Other known repositories

- [init-6/udept](https://gitlab.com/init-6/udept) on GitLab — the
  immediate ancestor of this branch and the basis for the 0.6.0
  modernization.
- [lkraav/udept](https://github.com/lkraav/udept) on GitHub — another
  community fork.

## Requirements

- `>=app-shells/bash-4.2` (the script enables `extglob` and uses
  associative arrays);
- `>=sys-apps/portage` with `portageq` on `$PATH`;
- a populated `metadata/md5-cache` in each repository (the standard
  `emerge --sync` / `eix-sync` flow produces this).

## Build and install

Standard autotools:

```sh
autoreconf -i            # configure is generated, not tracked
./configure              # --disable-{bash,zsh}-completion to skip either
make
sudo make install
```

`make install` lays down `bin/dep`, the man page (`dep.1`), and the
bash-completion script. The man page is generated from the option tables
in `src/dep.in` at build time, so it is always in sync with `dep --help`.

`configure` and the `Makefile.in` set are generated, not tracked in git,
so `autoreconf -i` is required after a fresh clone (and after editing
`configure.ac` / `Makefile.am`). A release tarball ships them already, so
building from the tarball can skip that step.

## Quick examples

```sh
# What depends on dev-libs/openssl?
dep -L openssl

# What does sys-apps/portage pull in?
dep -l portage

# Full dependency tree, two levels deep, only build-time deps included:
dep -t --depth=2 +b sys-apps/portage

# Which package owns this file?
dep -F /usr/bin/emerge

# Which versions of bash are visible, and what is their keyword status?
dep -e bash
dep -k bash

# Preview entries in the world file that another installed package
# already depends on (dry-run is the default):
dep --pruneworld

# Review interactively, or apply non-interactively:
dep --pruneworld --ask
dep --pruneworld --force

# Trim redundant entries from /etc/portage/package.{use,keywords,...}:
dep --filter-etc-portage

# In a personal overlay: list ebuilds that no installed package wants
# and that are not the most recent visible version:
dep --overlay-clean /var/db/repos/my-overlay
```

`dep --help` lists all actions and info types; the man page (`man dep`)
goes into more detail on the option semantics and on the dependency
language `dep` understands.

## Testing

The test matrix has four complementary gates: 333 isolated Bats unit tests,
11 property-invariant tests for configuration transforms, 47 smoke tests
against a real Portage tree, and `make check-oracle`, which compares at least
100 installed plus 100 visible CPVs against Python Portage. The older
`tests/smoke.sh` harness also captures a diffable host snapshot:

```sh
make check
make check-properties
make check-smoke
make check-oracle
make check-dist-inventory
make distcheck
```

This is what the modernization phases were validated against. The repository
keeps one portable CI snapshot at `tests/baseline.ci`; host-specific snapshots
created by `make smoke-baseline` use the ignored `tests/baseline.local` path.

## Authors and license

`dep` and the surrounding tooling are copyright Ed Catmur
&lt;ed@catmur.co.uk&gt; and contributors. The 0.6.0 modernization was carried
out by Ivan S. Titov.

Distributed under the terms of the GNU General Public License version 3 —
see `LICENSE`. NO WARRANTY.
