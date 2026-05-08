SUBDIRS = src doc completion packaging

EXTRA_DIST = \
	ChangeLog.20060126 \
	tests/smoke.sh \
	tests/unit/test_helper.bash \
	tests/unit/scaffolding.bats \
	tests/unit/dep_to_cps.bats \
	tests/unit/dep_satisfies.bats \
	tests/unit/world_sets_expand.bats \
	tests/unit/format_atom_for_emerge.bats \
	tests/unit/required_use.bats

# 'make check' runs the bats unit-test suite. Override BATS to point at
# a non-system bats binary if needed.
BATS = bats

check-local:
	@command -v $(BATS) >/dev/null || { \
	  echo "error: $(BATS) not on PATH; install dev-util/bats" >&2; \
	  exit 1; \
	}
	$(BATS) $(srcdir)/tests/unit/

# 'make ebuild' delegates to packaging/Makefile.am, which expects
# OVERLAY_DIR to be set:
#   make ebuild OVERLAY_DIR=/var/db/repos/<your-overlay>/app-portage/udept
ebuild:
	$(MAKE) -C packaging ebuild
