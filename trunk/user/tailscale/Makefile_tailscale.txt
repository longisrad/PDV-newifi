THISDIR = $(shell pwd)

TS_TARBALL = $(THISDIR)/tailscale_mipsle.tar.gz
TS_EXTRACTED = $(THISDIR)/tailscale_extracted

all:

clean:
	rm -rf $(TS_EXTRACTED)

romfs:
	@if [ ! -f $(TS_TARBALL) ]; then \
		echo "ERROR: $(TS_TARBALL) not found!"; \
		echo "Run: wget -O $(TS_TARBALL) https://github.com/lmq8267/tailscale/releases/latest/download/tailscale_mipsle.tar.gz"; \
		exit 1; \
	fi
	# Extract binary lúc build
	mkdir -p $(TS_EXTRACTED)
	tar -xzf $(TS_TARBALL) -C $(TS_EXTRACTED) 2>/dev/null || true
	# Copy tailscale và tailscaled vào squashfs
	if [ -f $(TS_EXTRACTED)/tailscale ]; then \
		$(ROMFSINST) -p +x $(TS_EXTRACTED)/tailscale   /usr/sbin/tailscale; \
		$(ROMFSINST) -p +x $(TS_EXTRACTED)/tailscaled  /usr/sbin/tailscaled; \
	else \
		find $(TS_EXTRACTED) -name "tailscale" -not -name "tailscaled" \
			-exec $(ROMFSINST) -p +x {} /usr/sbin/tailscale \; ; \
		find $(TS_EXTRACTED) -name "tailscaled" \
			-exec $(ROMFSINST) -p +x {} /usr/sbin/tailscaled \; ; \
	fi
	# Copy script
	$(ROMFSINST) -p +x $(THISDIR)/tailscale.sh /usr/bin/tailscale.sh
