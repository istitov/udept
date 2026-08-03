## udept 0.8.0 — Trust, but Verify

This release keeps udept's complete Bash-native feature set while hardening
the decisions and writes users rely on.

- HTML colour output is escaped at one streaming boundary; package metadata,
  paths, arguments, diagnostics, and terminal titles cannot become markup.
- Dependency resolution now shares one EAPI 8 matcher for version operators,
  slots/subslots, repositories, and USE dependencies. Blockers, OR groups,
  all visible virtual ebuilds, profile/repository USE, masks, forces, and
  FEATURES-driven `test` state are retained and evaluated.
- Mutating actions default to dry-run. `--ask` reviews interactively and the
  new long-only `--force` applies non-interactively; conflicting modes fail
  with status 2.
- Configuration replacement is atomic and same-directory, preserves metadata
  and valid in-root symlinks, rejects unsafe symlinks, validates content, and
  performs at most one privilege-escalation attempt.
- Explicit EROOT, EPREFIX, and PORTAGE_CONFIGROOT values are authoritative;
  CONTENTS paths containing whitespace are counted correctly.
- CI adds a differential Python Portage oracle (test-only), source/archive test
  inventory equality, warning-clean ShellCheck, and adversarial regression
  fixtures. The runtime remains Bash-only.

No command, output mode, virtual feature, cleanup feature, or completion was
removed.
