EXTRA_DIST = udept.ebuild.in metadata.xml

# Drop a freshly-versioned ebuild + metadata.xml into a local overlay and
# run 'ebuild ... manifest' to fetch the dist tarball and write Manifest.
# Set OVERLAY_DIR to your overlay's app-portage/udept directory, e.g.
#   make ebuild OVERLAY_DIR=/var/db/repos/<your-overlay>/app-portage/udept
ebuild:
	@test -n "$(OVERLAY_DIR)" || { \
	  echo 'error: set OVERLAY_DIR=/path/to/<overlay>/app-portage/udept' >&2; \
	  exit 1; \
	}
	mkdir -p $(OVERLAY_DIR)
	cp $(srcdir)/udept.ebuild.in $(OVERLAY_DIR)/udept-$(VERSION).ebuild
	cp $(srcdir)/metadata.xml $(OVERLAY_DIR)/metadata.xml
	ebuild $(OVERLAY_DIR)/udept-$(VERSION).ebuild manifest

