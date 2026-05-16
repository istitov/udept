# udept

[![CI](https://github.com/istitov/udept/actions/workflows/ci.yml/badge.svg)](https://github.com/istitov/udept/actions/workflows/ci.yml)

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
— a Portage analysis engine that is itself a single ~3500-line bash
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

See `ChangeLog` for the full per-release history.

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
./configure              # --disable-{bash,zsh}-completion to skip either
make
sudo make install
```

`make install` lays down `bin/dep`, the man page (`dep.1`), and the
bash-completion script. The man page is generated from the option tables
in `src/dep.in` at build time, so it is always in sync with `dep --help`.

To regenerate `configure` and `Makefile.in` after editing `configure.ac`
or `Makefile.am`, run `autoreconf -i`.

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

# Show entries in the world file that another installed package
# already depends on (candidates for pruning):
dep --pruneworld --pretend

# Trim redundant entries from /etc/portage/package.{use,keywords,...}:
dep --filter-etc-portage --pretend

# In a personal overlay: list ebuilds that no installed package wants
# and that are not the most recent visible version:
dep --overlay-clean /var/db/repos/my-overlay
```

`dep --help` lists all actions and info types; the man page (`man dep`)
goes into more detail on the option semantics and on the dependency
language `dep` understands.

## Testing

There is a smoke harness at `tests/smoke.sh` that runs a representative
set of `dep` invocations against the current system's Portage state and
captures their output for diffing against a baseline. It does not assert
correctness, only stability:

```sh
tests/smoke.sh -o /tmp/snapshot         # produce a snapshot
diff -u tests/baseline.phase16 /tmp/snapshot  # compare to last baseline
```

This is what the modernization phases were validated against; baselines
for each phase live in `tests/`.

## Authors and license

`dep` and the surrounding tooling are copyright Ed Catmur
&lt;ed@catmur.co.uk&gt; and contributors. The 0.6.0 modernization was carried
out by Ivan S. Titov.

Distributed under the terms of the GNU General Public License
version 3 — see `LICENSE`. NO WARRANTY.
