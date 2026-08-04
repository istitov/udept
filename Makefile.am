SUBDIRS = src doc completion packaging

EXTRA_DIST = \
	.editorconfig \
	.shellcheckrc \
	CONTRIBUTING.md \
	RELEASE_NOTES-0.8.0.md \
	SECURITY.md \
	tests/baseline.ci \
	tests/smoke.sh \
	tests/smoke-diff.sh \
	tests/unit/test_helper.bash \
	tests/unit/scaffolding.bats \
	tests/unit/dep_to_cps.bats \
	tests/unit/dep_satisfies.bats \
	tests/unit/world_sets_expand.bats \
	tests/unit/crunch_depends.bats \
	tests/unit/format_atom_for_emerge.bats \
	tests/unit/format_depatom.bats \
	tests/unit/format_revdep.bats \
	tests/unit/format_taint.bats \
	tests/unit/print_depstring.bats \
	tests/unit/required_use.bats \
	tests/unit/required_use_action.bats \
	tests/unit/resolve_depatom.bats \
	tests/unit/slot_satisfies.bats \
	tests/unit/smoke_diff.bats \
	tests/unit/comm_ver.bats \
	tests/unit/usecomponent.bats \
	tests/unit/db_grep.bats \
	tests/unit/ask_install_new_file.bats \
	tests/unit/action_modes.bats \
	tests/unit/atom_match.bats \
	tests/unit/matcher_unification.bats \
	tests/unit/filter_world.bats \
	tests/unit/install_new_file.bats \
	tests/unit/html_render.bats \
	tests/unit/eroot_paths.bats \
	tests/unit/info_action_size.bats \
	tests/unit/filter_etc_file.bats \
	tests/unit/extract_var.bats \
	tests/unit/allvirtuals.bats \
	tests/unit/memoise.bats \
	tests/unit/virtual_version.bats \
	tests/unit/info_action_changelog.bats \
	tests/unit/makeideal.bats \
	tests/smoke/test_helper.bash \
	tests/smoke/help.bats \
	tests/smoke/info_actions.bats \
	tests/smoke/virtuals.bats \
	tests/smoke/existence.bats \
	tests/smoke/output_modes.bats \
	tests/smoke/html_safety.bats \
	tests/smoke/errors.bats \
	tests/smoke/actions.bats \
	tests/property/test_helper.bash \
	tests/property/comments.bats \
	tests/property/use_filter.bats \
	tests/property/keywords.bats \
	tests/property/world.bats

EXTRA_DIST += \
	tests/oracle/portage_atom_cases.py \
	tests/oracle/check_atom_cases.sh \
	tests/check-dist-inventory.sh

# 'make check' runs the bats unit-test suite. Override BATS to point at
# a non-system bats binary if needed.
BATS = bats

check-local:
	@command -v $(BATS) >/dev/null || { \
	  echo "error: $(BATS) not on PATH; install dev-util/bats" >&2; \
	  exit 1; \
	}
	$(BATS) $(srcdir)/tests/unit/

# 'make check-smoke' runs the bats smoke tier against the BUILT src/dep
# on the host's real Portage tree. Requires src/dep to be built (run
# ./configure && make first), bats installed, and the host to have a
# populated /var/db/pkg. Each smoke test skips itself rather than
# failing the suite when a per-test prerequisite (e.g. virtual/editor)
# isn't installed — fresh stage3 containers in CI work fine.
#
# Unlike `make check` (which sources dep.in with stubs in-process),
# this tier validates that the binary actually starts, parses its argv,
# and consumes real eix / qatom / /var/db/pkg output without crashing.
.PHONY: check-smoke
check-smoke:
	@command -v $(BATS) >/dev/null || { \
	  echo "error: $(BATS) not on PATH; install dev-util/bats" >&2; \
	  exit 1; \
	}
	@test -x $(top_builddir)/src/dep || { \
	  echo "error: src/dep not built; run ./configure && make first" >&2; \
	  exit 1; \
	}
	$(BATS) $(srcdir)/tests/smoke/

# 'make check-properties' runs the bats property-invariant tier: it drives the
# REAL config-mutating filters (filter_etc_portage / filter_world) end-to-end
# over synthetic, anonymous fixtures and asserts ORACLE-FREE invariants —
# idempotence, atom-inventory subset, no introduced duplicate flag, and
# comment-preservation — instead of golden output. This catches the
# transform-corruption class both other tiers miss: `make check` stubs the
# per-file filter callbacks, and the smoke tier never applies a mutation.
#
# Like the unit tier it sources dep.in (udept's paths are hard globals
# relocatable only as a unit via EROOT, so a built-binary run can't sandbox the
# write target while keeping metadata on the real tree). The redundancy filters
# need real Portage metadata, so the package.use / keywords / world tests
# self-skip when portageq or a populated /var/db/pkg is unavailable; the
# comment-preservation tests have no such dependency and always run.
.PHONY: check-properties
check-properties:
	@command -v $(BATS) >/dev/null || { \
	  echo "error: $(BATS) not on PATH; install dev-util/bats" >&2; \
	  exit 1; \
	}
	$(BATS) $(srcdir)/tests/property/

.PHONY: check-oracle
check-oracle:
	@command -v python3 >/dev/null || { echo "error: python3 not on PATH" >&2; exit 1; }
	@python3 -c 'import portage' 2>/dev/null || { echo "error: Python Portage module unavailable" >&2; exit 1; }
	python3 $(srcdir)/tests/oracle/portage_atom_cases.py \
	  | bash $(srcdir)/tests/oracle/check_atom_cases.sh $(srcdir)/src/dep.in

.PHONY: check-dist-inventory
check-dist-inventory: dist
	bash $(srcdir)/tests/check-dist-inventory.sh \
	  $(PACKAGE_TARNAME)-$(PACKAGE_VERSION).tar.xz $(srcdir)

# Smoke-test targets. The smoke harness exercises a fixed battery of `dep`
# invocations against the live Portage tree and emits a stable, diffable
# snapshot. Use cases:
#
#   make smoke
#       Run the harness, print the snapshot to stdout. Inspect by eye or
#       redirect.
#
#   make smoke-baseline
#       Run the harness, write the snapshot to $(BASELINE) (default
#       tests/baseline.local). Local baselines are gitignored — they
#       contain installed-package inventory and shouldn't be committed.
#
#   make smoke-diff
#       Diff a fresh snapshot against $(BASELINE). The diff helper strips
#       volatile header lines (timestamp, host kernel, cpv-resolution
#       summary) from both sides; everything else (line counts, sha256
#       markers, command output) is real signal. Exit 0 on no diff, 1 on
#       diff, 2 on invocation error.
#
# Override BASELINE on the command line to use a different file:
#   make smoke-diff BASELINE=tests/baseline.ci
BASELINE ?= tests/baseline.local

.PHONY: smoke smoke-baseline smoke-diff

smoke:
	@[ -f $(srcdir)/src/dep ] || { \
	  echo "src/dep not built — run 'make' first" >&2; \
	  exit 1; \
	}
	@chmod +x $(srcdir)/src/dep
	@$(srcdir)/tests/smoke.sh

smoke-baseline:
	@[ -f $(srcdir)/src/dep ] || { \
	  echo "src/dep not built — run 'make' first" >&2; \
	  exit 1; \
	}
	@chmod +x $(srcdir)/src/dep
	@$(srcdir)/tests/smoke.sh > $(BASELINE)
	@printf 'Wrote baseline: %s (%s lines)\n' '$(BASELINE)' "$$(wc -l <'$(BASELINE)')"

smoke-diff:
	@[ -f $(BASELINE) ] || { \
	  echo "no baseline at $(BASELINE) — run 'make smoke-baseline' first" >&2; \
	  exit 2; \
	}
	@$(srcdir)/tests/smoke-diff.sh $(BASELINE)

# 'make ebuild' delegates to packaging/Makefile.am, which expects
# OVERLAY_DIR to be set:
#   make ebuild OVERLAY_DIR=/var/db/repos/<your-overlay>/app-portage/udept
ebuild:
	$(MAKE) -C packaging ebuild

# 'make toc' prints the topical section index from src/dep.in.  Each
# section is a banner whose name line starts with `# === ` and is
# preceded by a `# ==========...` fence (the fence disambiguates from
# inline `# === ` continuation lines inside a banner body).
.PHONY: toc
toc:
	@awk '/^# =====/ {f=1; next} \
	      f && /^# === [A-Za-z]/ {printf "  %4d  %s\n", NR, substr($$0, 7); f=0; next} \
	      {f=0}' $(srcdir)/src/dep.in
