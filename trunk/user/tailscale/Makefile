THISDIR = $(shell pwd)

# Binary MIPS từ repo lmq8267/tailscale
# Download thủ công trước khi build:
#   wget -O trunk/user/tailscale/tailscale_mipsle.tar.gz \
#     https://github.com/lmq8267/tailscale/releases/latest/download/tailscale_mipsle.tar.gz

TS_TARBALL = $(THISDIR)/tailscale_mipsle.tar.gz

all:

clean:

romfs:
	@if [ ! -f $(TS_TARBALL) ]; then \
		echo "ERROR: $(TS_TARBALL) not found!"; \
		echo "Run: wget -O $(TS_TARBALL) https://github.com/lmq8267/tailscale/releases/latest/download/tailscale_mipsle.tar.gz"; \
		exit 1; \
	fi
	# Copy tarball vào squashfs (read-only, persist qua flash)
	# tailscale.sh sẽ copy sang /etc/storage/ lần đầu chạy
	$(ROMFSINST) $(TS_TARBALL) /usr/share/tailscale/tailscale.tar.gz
	# Copy script
	$(ROMFSINST) -p +x $(THISDIR)/tailscale.sh /usr/bin/tailscale.sh
