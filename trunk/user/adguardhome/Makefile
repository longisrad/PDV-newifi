THISDIR = $(shell pwd)
AGH_TARBALL = $(THISDIR)/AdGuardHome_linux_mipsle_softfloat.tar.gz
AGH_BIN = $(THISDIR)/AdGuardHome_extracted/AdGuardHome/AdGuardHome

all:

clean:
	rm -rf $(THISDIR)/AdGuardHome_extracted

romfs:
	# Extract binary từ tarball
	mkdir -p $(THISDIR)/AdGuardHome_extracted
	tar -xzf $(AGH_TARBALL) -C $(THISDIR)/AdGuardHome_extracted
	# Copy binary vào firmware
	$(ROMFSINST) -p +x $(AGH_BIN) /usr/bin/AdGuardHome
	# Copy script vào firmware
	$(ROMFSINST) -p +x $(THISDIR)/adguardhome.sh /usr/bin/adguardhome.sh
