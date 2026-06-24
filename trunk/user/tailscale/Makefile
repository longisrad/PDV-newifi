THISDIR = $(shell pwd)

all:

clean:

romfs:
	# 1. Sao chép tệp nén tailscale.tar.gz vào phân vùng etc_ro của hệ thống
	$(ROMFSINST) $(THISDIR)/tailscale.tar.gz /etc_ro/tailscale.tar.gz
	
	# 2. Sao chép kịch bản quản lý vào /usr/bin và cấp quyền thực thi (+x)
	$(ROMFSINST) -p +x $(THISDIR)/tailscale.sh /usr/bin/tailscale.sh
