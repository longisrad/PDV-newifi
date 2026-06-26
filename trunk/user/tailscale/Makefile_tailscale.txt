THISDIR = $(shell pwd)

# lmq8267/tailscale: binary đơn lẻ tailscaled_full
# Combined binary - gọi với argv[0] để chọn mode tailscale/tailscaled
TS_BIN = $(THISDIR)/tailscaled_full

all:

clean:

romfs:
	@if [ ! -f $(TS_BIN) ]; then \
		echo "ERROR: $(TS_BIN) not found!"; \
		exit 1; \
	fi
	# Install binary vào squashfs
	$(ROMFSINST) -p +x $(TS_BIN) /usr/sbin/tailscaled
	# tailscale symlink → tailscaled (combined binary dùng argv[0])
	ln -sf tailscaled $(ROMFSDIR)/usr/sbin/tailscale
	# Copy script
	$(ROMFSINST) -p +x $(THISDIR)/tailscale.sh /usr/bin/tailscale.sh
