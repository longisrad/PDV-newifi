THISDIR = $(shell pwd)

TS_TARBALL = $(THISDIR)/tailscale_mipsle.tar.gz

all:

clean:

romfs:
	@if [ ! -f $(TS_TARBALL) ]; then \
		echo "ERROR: $(TS_TARBALL) not found!"; \
		echo "Run: wget -O $(TS_TARBALL) https://github.com/lmq8267/tailscale/releases/latest/download/tailscale_mipsle.tar.gz"; \
		exit 1; \
	fi
	mkdir -p $(ROMFSDIR)/usr/share/tailscale
	$(ROMFSINST) $(TS_TARBALL) /usr/share/tailscale/tailscale.tar.gz
	$(ROMFSINST) -p +x $(THISDIR)/tailscale.sh /usr/bin/tailscale.sh
