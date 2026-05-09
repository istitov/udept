SUBDIRS = src doc completion packaging

EXTRA_DIST = \
	ChangeLog.20060126 \
	tests/smoke.sh \
	tests/smoke-diff.sh \
	tests/unit/test_helper.bash \
	tests/unit/scaffolding.bats \
	tests/unit/dep_to_cps.bats \
	tests/unit/dep_satisfies.bats \
	tests/unit/world_sets_expand.bats \
	tests/unit/format_atom_for_emerge.bats \
	tests/unit/required_use.bats \
	tests/unit/required_use_action.bats \
	tests/unit/slot_satisfies.bats \
	tests/unit/smoke_diff.bats

# 'make check' runs the bats unit-test suite. Override BATS to point at
# a non-system bats binary if needed.
BATS = bats

check-local:
	@command -v $(BATS) >/dev/null || { \
	  echo "error: $(BATS) not on PATH; install dev-util/bats" >&2; \
	  exit 1; \
	}
	$(BATS) $(srcdir)/tests/unit/

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
