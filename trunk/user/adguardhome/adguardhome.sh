#!/bin/sh

AGH_BIN_SRC="/usr/bin/AdGuardHome"   # binary trong firmware, chạy thẳng
AGH_TMP="/etc/storage/AdGuardHome"   # work dir - persist qua reboot, đủ space
AGH_BIN="$AGH_BIN_SRC"               # chạy thẳng từ squashfs, không copy ra RAM
AGH_CFG="/etc/storage/AdGuardHome/AdGuardHome.yaml"  # config persist qua reboot

change_dns() {
    local mode="$(nvram get adg_redirect)"
    if [ "$mode" = "1" ]; then
        # Mode 1: dnsmasq forward lên AGH port 5335
        sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
        sed -i '/server=127.0.0.1#5335/d' /etc/storage/dnsmasq/dnsmasq.conf
        cat >> /etc/storage/dnsmasq/dnsmasq.conf << EOF
no-resolv
server=127.0.0.1#5335
EOF
        /sbin/restart_dhcpd
        logger -t "AdGuardHome" "DNS: dnsmasq forwarding to AGH port 5335"
    elif [ "$mode" = "2" ]; then
        # Mode 2: tắt dnsmasq DNS listener, AGH listen port 53 trực tiếp
        sed -i '/^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
        echo "port=0" >> /etc/storage/dnsmasq/dnsmasq.conf
        /sbin/restart_dhcpd
        logger -t "AdGuardHome" "DNS: dnsmasq port disabled, AGH takes port 53"
    fi
}

del_dns() {
    sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/server=127.0.0.1#5335/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^port=0/d' /etc/storage/dnsmasq/dnsmasq.conf
    /sbin/restart_dhcpd
}

set_iptable() {
    if [ "$(nvram get adg_redirect)" = "2" ]; then
        IPS="$(ifconfig | grep "inet addr" | grep -v ":127" | grep "Bcast" | awk '{print $2}' | awk -F: '{print $2}')"
        for IP in $IPS; do
            iptables -t nat -A PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
            iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        done
        IPS="$(ifconfig | grep "inet6 addr" | grep -v " fe80::" | grep -v " ::1" | grep "Global" | awk '{print $3}')"
        for IP in $IPS; do
            ip6tables -t nat -A PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
            ip6tables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        done
        logger -t "AdGuardHome" "Redirecting port 53 to 5335"
    fi
}

clear_iptable() {
    IPS="$(ifconfig | grep "inet addr" | grep -v ":127" | grep "Bcast" | awk '{print $2}' | awk -F: '{print $2}')"
    for IP in $IPS; do
        iptables -t nat -D PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        iptables -t nat -D PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
    done
    IPS="$(ifconfig | grep "inet6 addr" | grep -v " fe80::" | grep -v " ::1" | grep "Global" | awk '{print $3}')"
    for IP in $IPS; do
        ip6tables -t nat -D PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        ip6tables -t nat -D PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
    done
}

load_binary() {
    if [ ! -f "$AGH_BIN_SRC" ]; then
        logger -t "AdGuardHome" "ERROR: Binary not found at $AGH_BIN_SRC"
        nvram set adg_enable=0
        exit 1
    fi
    mkdir -p "$AGH_TMP"
    logger -t "AdGuardHome" "Running binary directly from firmware (no RAM copy needed)"
}

getconfig() {
    mkdir -p /etc/storage/AdGuardHome
    # Let AGH auto-generate config on first run
    # Only pre-set language to English if no config exists
    if [ ! -f "$AGH_CFG" ] || [ ! -s "$AGH_CFG" ]; then
        logger -t "AdGuardHome" "No config found, AGH will auto-generate on first run"
    fi
}

start_adg() {
    if pgrep AdGuardHome >/dev/null 2>&1; then
        logger -t "AdGuardHome" "Already running, skipping start"
        return
    fi
    load_binary
    getconfig
    change_dns
    set_iptable
    # Set CA certificates để AGH verify HTTPS khi download blocklists
    export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    export SSL_CERT_DIR=/etc/ssl/certs
    logger -t "AdGuardHome" "Starting AdGuardHome..."
    if [ -f "$AGH_CFG" ] && [ -s "$AGH_CFG" ]; then
        "$AGH_BIN" -c "$AGH_CFG" -w "$AGH_TMP" --no-check-update &
        logger -t "AdGuardHome" "AdGuardHome started with config (PID: $!)"
    else
        "$AGH_BIN" -w "$AGH_TMP" --no-check-update &
        logger -t "AdGuardHome" "AdGuardHome started in setup mode port 3000 (PID: $!)"
    fi
}

stop_adg() {
    logger -t "AdGuardHome" "Stopping AdGuardHome..."
    killall -9 AdGuardHome 2>/dev/null
    del_dns
    clear_iptable
    # Không xóa AGH_TMP vì chứa config và data
    # Chỉ xóa lock/pid files nếu có
    rm -f "$AGH_TMP"/*.pid 2>/dev/null
    logger -t "AdGuardHome" "AdGuardHome stopped"
}

case $1 in
    start)
        start_adg
        ;;
    stop)
        stop_adg
        ;;
    restart)
        stop_adg
        sleep 1
        start_adg
        ;;
    status)
        if pgrep AdGuardHome >/dev/null 2>&1; then
            echo "AdGuardHome is running"
        else
            echo "AdGuardHome is stopped"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        ;;
esac
