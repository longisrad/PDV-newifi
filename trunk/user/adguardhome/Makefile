THISDIR = $(shell pwd)
all:

clean:
	rm -rf $(THISDIR)/AdGuardHome_extracted

romfs:
	# Chỉ copy script và CA certs vào firmware
	# Binary AGH sẽ tự download về NAND lần đầu boot
	$(ROMFSINST) -p +x $(THISDIR)/adguardhome.sh /usr/bin/adguardhome.sh
	$(ROMFSINST) $(THISDIR)/ca-certificates.crt /etc_ro/ca-certificates.crt
