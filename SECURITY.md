# Security Policy

## Supported versions

Security fixes land on the active series only.

| Version | Supported          |
|---------|--------------------|
| 0.7.x   | :white_check_mark: |
| < 0.7   | :x:                |

## Reporting a vulnerability

Use GitHub's Private Vulnerability Reporting:

<https://github.com/istitov/udept/security/advisories/new>

Expect a first response within 14 days.  Reports that include a
reproducer (the exact `dep` invocation plus the relevant
`/var/db/pkg` metadata or a minimal `metadata/md5-cache/<cpv>` entry
that triggers the issue) get triaged first.

If GitHub PVR is unavailable, email <iohann.s.titov@gmail.com>.

## In scope

- **sed / shell injection** via crafted CPV, USE, IUSE, KEYWORDS,
  SLOT, `*DEPEND`, or PROVIDE strings read from `/var/db/pkg/*/*/`,
  profile files, `metadata/md5-cache/`, or argv.  Any unescaped
  interpolation of these fields into `sed`, `grep`, `awk`, or `eval`
  contexts qualifies.

- **HTML-mode escaping bypass** — `--colour=html` output that fails
  to escape HTML metacharacters from any of the fields above.  This
  matters when the output is published (CI dashboards, paste services,
  blog posts).

- **Out-of-root-path writes** — operations that mutate files outside
  the eight declared path roots: `$VARDB_DIR`, `$EDB_DIR`,
  `$PORTAGE_LIB_DIR`, `$PORTAGE_LOG_DIR`, `$ETC_PORTAGE_DIR`,
  `$WORLD_FILE`, `$WORLD_SETS_FILE`, `$ETC_PORTAGE_SETS_DIR`.  Path
  traversal via `../` in CPV args; etc.

- **`--depclean` / `--purge` / `--pruneworld` spurious removals** —
  recommending or selecting for removal a package that shouldn't be
  removed (running kernel, system-set members, virtuals stuck in
  pretend output, transitive world-set deps).  Real-world data-loss
  class; reports here are very welcome.

## Out of scope

- Performance issues.  `dep -L` and `dep -T` scale with reverse-dep
  count by design.

- Issues already fixed in the supported version.  Check the
  [`ChangeLog`](ChangeLog) before reporting.

- Anything that requires pre-existing root-equivalent access on the
  same host.  udept's mutating modes (`--depclean`, `--filter-etc-
  portage`, etc.) run as root by design.

- **`--exec ...` running arbitrary code via `eval`** — intentional.
  The user supplies a shell snippet; if it does something destructive,
  that's the snippet, not udept.

- Color leakage from non-TTY output or terminals with `$TERM=dumb` —
  superseded by the NO_COLOR + isatty gate already in place.

## Disclosure

Once a fix is available, an advisory is published on the GitHub
Security tab (with a CVE if it warrants one) and the corresponding
ChangeLog entry references it.
