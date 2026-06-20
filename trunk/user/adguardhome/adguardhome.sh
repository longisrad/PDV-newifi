#!/bin/sh

AGH_BIN_SRC="/usr/bin/AdGuardHome"   # binary UPX trong firmware
AGH_TMP="/tmp/AdGuardHome"            # thư mục RAM
AGH_BIN="$AGH_TMP/AdGuardHome"       # binary sau khi copy ra RAM
AGH_CFG="/etc/storage/AdGuardHome/AdGuardHome.yaml"  # config persist qua reboot

change_dns() {
    if [ "$(nvram get adg_redirect)" = "1" ]; then
        sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
        sed -i '/server=127.0.0.1#5335/d' /etc/storage/dnsmasq/dnsmasq.conf
        cat >> /etc/storage/dnsmasq/dnsmasq.conf << EOF
no-resolv
server=127.0.0.1#5335
EOF
        /sbin/restart_dhcpd
        logger -t "AdGuardHome" "DNS forwarding to port 5335"
    fi
}

del_dns() {
    sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/server=127.0.0.1#5335/d' /etc/storage/dnsmasq/dnsmasq.conf
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
        logger -t "AdGuardHome" "ERROR: Binary not found in firmware at $AGH_BIN_SRC"
        nvram set adg_enable=0
        exit 1
    fi
    mkdir -p "$AGH_TMP"
    logger -t "AdGuardHome" "Loading binary from firmware to RAM..."
    cp "$AGH_BIN_SRC" "$AGH_BIN"
    chmod 755 "$AGH_BIN"
    logger -t "AdGuardHome" "Binary loaded to RAM successfully"
}

getconfig() {
    mkdir -p /etc/storage/AdGuardHome
    if [ ! -f "$AGH_CFG" ] || [ ! -s "$AGH_CFG" ]; then
        logger -t "AdGuardHome" "Creating default config..."
        cat > "$AGH_CFG" << EOF
bind_host: 0.0.0.0
bind_port: 3030
auth_name: admin
auth_pass: admin
language: en
rlimit_nofile: 0
dns:
  bind_host: 0.0.0.0
  port: 5335
  protection_enabled: true
  filtering_enabled: true
  blocking_mode: nxdomain
  blocked_response_ttl: 10
  querylog_enabled: true
  ratelimit: 20
  ratelimit_whitelist: []
  refuse_any: true
  bootstrap_dns:
  - 1.1.1.1
  - 8.8.8.8
  all_servers: true
  allowed_clients: []
  disallowed_clients: []
  blocked_hosts: []
  parental_sensitivity: 0
  parental_enabled: false
  safesearch_enabled: false
  safebrowsing_enabled: false
  resolveraddress: ""
  upstream_dns:
  - 1.1.1.1
  - 8.8.8.8
tls:
  enabled: false
  server_name: ""
  force_https: false
  port_https: 443
  port_dns_over_tls: 853
  certificate_chain: ""
  private_key: ""
filters:
- enabled: true
  url: https://adguardteam.github.io/AdGuardSDNSFilter/Filters/filter.txt
  name: AdGuard DNS filter
  id: 1
- enabled: true
  url: https://adaway.org/hosts.txt
  name: AdAway Default Blocklist
  id: 2
user_rules: []
dhcp:
  enabled: false
clients: []
log_file: ""
verbose: false
schema_version: 3
EOF
        chmod 644 "$AGH_CFG"
        logger -t "AdGuardHome" "Default config created"
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
    logger -t "AdGuardHome" "Starting AdGuardHome..."
    "$AGH_BIN" -c "$AGH_CFG" -w "$AGH_TMP" --no-check-update &
    logger -t "AdGuardHome" "AdGuardHome started (PID: $!)"
}

stop_adg() {
    logger -t "AdGuardHome" "Stopping AdGuardHome..."
    killall -9 AdGuardHome 2>/dev/null
    del_dns
    clear_iptable
    rm -rf "$AGH_TMP"
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
