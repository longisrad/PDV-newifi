THISDIR = $(shell pwd)
all:

clean:
	rm -rf $(THISDIR)/AdGuardHome_extracted

romfs:
	# Extract binary từ tarball
	mkdir -p $(THISDIR)/AdGuardHome_extracted
	tar -xzf $(THISDIR)/AdGuardHome_linux_mipsle_softfloat.tar.gz -C $(THISDIR)/AdGuardHome_extracted 2>/dev/null || true
	# Copy binary vào firmware (từ extracted hoặc trực tiếp)
	if [ -f $(THISDIR)/AdGuardHome_extracted/AdGuardHome/AdGuardHome ]; then \
		$(ROMFSINST) -p +x $(THISDIR)/AdGuardHome_extracted/AdGuardHome/AdGuardHome /usr/bin/AdGuardHome; \
	elif [ -f $(THISDIR)/AdGuardHome ]; then \
		$(ROMFSINST) -p +x $(THISDIR)/AdGuardHome /usr/bin/AdGuardHome; \
	fi
	# Copy script
	$(ROMFSINST) -p +x $(THISDIR)/adguardhome.sh /usr/bin/adguardhome.sh
	# Tạo thư mục và copy chứng chỉ CA cho AGH update blocklist
	mkdir -p $(ROMFSDIR)/etc/ssl/certs
	$(ROMFSINST) $(THISDIR)/ca-certificates.crt /etc/ssl/certs/ca-certificates.crt
