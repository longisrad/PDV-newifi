THISDIR = $(shell pwd)

TS_TARBALL = $(THISDIR)/tailscale_mipsle.tar.gz
TS_EXTRACTED = $(THISDIR)/tailscale_extracted

all:

clean:
	rm -rf $(TS_EXTRACTED)

romfs:
	@if [ ! -f $(TS_TARBALL) ]; then \
		echo "ERROR: $(TS_TARBALL) not found!"; \
		exit 1; \
	fi
	mkdir -p $(TS_EXTRACTED)
	tar -xzf $(TS_TARBALL) -C $(TS_EXTRACTED) 2>/dev/null || true
	@echo "Extracted files:"
	@find $(TS_EXTRACTED) -type f
	# GuNanOvO builds combine tailscale+tailscaled into 1 binary
	# Tìm binary chính (không phải .ipk, .sh)
	$(eval TS_BIN_FOUND := $(shell find $(TS_EXTRACTED) -type f -not -name "*.ipk" -not -name "*.sh" -not -name "*.md" | head -1))
	@echo "Found binary: $(TS_BIN_FOUND)"
	@if [ -n "$(TS_BIN_FOUND)" ]; then \
		cp "$(TS_BIN_FOUND)" "$(TS_EXTRACTED)/tailscale_bin"; \
		chmod +x "$(TS_EXTRACTED)/tailscale_bin"; \
	fi
	# Install: 1 binary phục vụ cả tailscale lẫn tailscaled
	$(ROMFSINST) -p +x $(TS_EXTRACTED)/tailscale_bin /usr/sbin/tailscale
	# tailscaled là symlink sang tailscale (combined binary)
	ln -sf tailscale $(ROMFSDIR)/usr/sbin/tailscaled 2>/dev/null || true
	$(ROMFSINST) -p +x $(THISDIR)/tailscale.sh /usr/bin/tailscale.sh
