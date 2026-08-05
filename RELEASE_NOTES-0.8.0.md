## udept 0.8.0 — Trust, but Verify

This release keeps udept's complete Bash-native feature set while hardening
the decisions and writes users rely on.

- HTML colour output is escaped at one streaming boundary; package metadata,
  paths, arguments, diagnostics, and terminal titles cannot become markup.
- Dependency resolution now shares one EAPI 8 matcher for version operators,
  slots/subslots, repositories, and USE dependencies. Blockers, OR groups,
  all visible virtual ebuilds, profile/repository USE, masks, forces, and
  FEATURES-driven `test` state are retained and evaluated.
- Effective USE follows Portage's own resolution: the whole profile parent
  stack in precedence order, `use.mask` applied after `use.force` and ARCH and
  stacked one profile node at a time, the `.stable` files gated on keyword
  visibility, make.conf's contribution separated from the profile's, and each
  USE_EXPAND variable treated as a complete set. Checked flag for flag against
  Python Portage over a 530-package sample of an installed set.
- Mutating actions default to dry-run. `--ask` reviews interactively and the
  new long-only `--force` applies non-interactively; conflicting modes fail
  with status 2. `-E` now judges a `package.use` flag redundant against what
  that package would resolve to without its own entry, so flags that are doing
  work are no longer offered for removal.
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
