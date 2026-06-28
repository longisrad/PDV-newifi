#!/bin/sh
#
# AdGuardHome for Padavan
# Tối ưu hóa chạy trực tiếp từ ROM (SquashFS)
#

# Tối ưu hóa bộ nhớ cho Go trên router cấu hình thấp
export GODEBUG=madvdontneed=1
export GOGC=15
export GOMEMLIMIT=45MiB

AGH_STORAGE="/etc/storage/AdGuardHome"
AGH_CFG="$AGH_STORAGE/AdGuardHome.yaml"
AGH_VERSION_FILE="$AGH_STORAGE/.version"

log() { logger -t "AdGuardHome" "$1"; }

# ================================================================
# Phát hiện thông minh vị trí của AdGuardHome
# Ưu tiên ROM (SquashFS) để tiết kiệm RAM, nếu không thấy mới dùng NAND/USB
# ================================================================
if [ -x "/usr/bin/AdGuardHome" ]; then
    AGH_BIN="/usr/bin/AdGuardHome"
elif [ -x "/usr/sbin/AdGuardHome" ]; then
    AGH_BIN="/usr/sbin/AdGuardHome"
else
    AGH_BIN="$AGH_STORAGE/AdGuardHome"
fi

change_dns() {
    local mode="$(nvram get adg_redirect)"
    if [ "$mode" = "1" ]; then
        sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
        sed -i '/server=127.0.0.1#5335/d' /etc/storage/dnsmasq/dnsmasq.conf
        printf 'no-resolv\nserver=127.0.0.1#5335\n' >> /etc/storage/dnsmasq/dnsmasq.conf
        /sbin/restart_dhcpd
        log "DNS: dnsmasq forwarding to AGH port 5335"
    elif [ "$mode" = "2" ]; then
        sed -i '/^port=/d' /etc/storage/dnsmasq/dnsmasq.conf
        echo "port=0" >> /etc/storage/dnsmasq/dnsmasq.conf
        /sbin/restart_dhcpd
        log "DNS: dnsmasq port disabled, AGH takes port 53"
    fi
}

del_dns() {
    sed -i '/no-resolv/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/server=127.0.0.1#5335/d' /etc/storage/dnsmasq/dnsmasq.conf
    sed -i '/^port=0/d' /etc/storage/dnsmasq/dnsmasq.conf
    /sbin/restart_dhcpd
}

set_iptable() {
    local mode="$(nvram get adg_redirect)"
    if [ "$mode" = "1" ]; then
        IPS="$(ifconfig | grep "inet addr" | grep -v ":127" | grep "Bcast" | awk '{print $2}' | awk -F: '{print $2}')"
        for IP in $IPS; do
            iptables -t nat -A PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
            iptables -t nat -A PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        done
        log "Mode 1: Redirecting port 53 to AGH port 5335"
    else
        log "Mode 2: AGH owns port 53 directly, no redirect needed"
    fi
}

clear_iptable() {
    IPS="$(ifconfig | grep "inet addr" | grep -v ":127" | grep "Bcast" | awk '{print $2}' | awk -F: '{print $2}')"
    for IP in $IPS; do
        iptables -t nat -D PREROUTING -p udp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
        iptables -t nat -D PREROUTING -p tcp -d $IP --dport 53 -j REDIRECT --to-ports 5335 >/dev/null 2>&1
    done
}

download_agh() {
    # Nếu binary nằm trong ROM, chặn không tải đè để tránh lỗi phân vùng Read-only
    if echo "$AGH_BIN" | grep -E -q "^/usr/"; then
        log "AGH is embedded in ROM, skipped remote downloading."
        return 0
    fi

    mkdir -p "$AGH_STORAGE"
    log "Fetching latest AGH version info..."

    local RELEASE_JSON
    RELEASE_JSON="$(curl -sf --max-time 15 https://api.github.com/repos/AdguardTeam/AdGuardHome/releases/latest 2>/dev/null)"

    if [ -z "$RELEASE_JSON" ]; then
        log "ERROR: Cannot reach GitHub API"
        return 1
    fi

    local LATEST_VER
    LATEST_VER="$(echo "$RELEASE_JSON" | grep '"tag_name"' | head -1 | cut -d'"' -f4)"

    if [ -z "$LATEST_VER" ]; then
        log "ERROR: Cannot parse version"
        return 1
    fi

    local CURRENT_VER=""
    [ -f "$AGH_VERSION_FILE" ] && CURRENT_VER="$(cat $AGH_VERSION_FILE)"

    if [ -f "$AGH_BIN" ] && [ "$CURRENT_VER" = "$LATEST_VER" ]; then
        log "AGH $LATEST_VER already up to date"
        return 0
    fi

    log "Downloading AGH $LATEST_VER..."
    local DL_URL="https://github.com/AdguardTeam/AdGuardHome/releases/download/${LATEST_VER}/AdGuardHome_linux_mipsle_softfloat.tar.gz"
    local TMP_TAR="/tmp/agh_dl.tar.gz"
    local TMP_DIR="/tmp/agh_extract"

    curl -sL --max-time 120 -o "$TMP_TAR" "$DL_URL"
    if [ $? -ne 0 ] || [ ! -s "$TMP_TAR" ]; then
        log "ERROR: Download failed"
        rm -f "$TMP_TAR"
        return 1
    fi

    mkdir -p "$TMP_DIR"
    tar -xzf "$TMP_TAR" -C "$TMP_DIR" 2>/dev/null
    rm -f "$TMP_TAR"

    if [ -f "$TMP_DIR/AdGuardHome/AdGuardHome" ]; then
        mv "$TMP_DIR/AdGuardHome/AdGuardHome" "$AGH_BIN"
        chmod +x "$AGH_BIN"
        echo "$LATEST_VER" > "$AGH_VERSION_FILE"
        rm -rf "$TMP_DIR"
        log "AGH $LATEST_VER installed to storage OK"
        return 0
    else
        log "ERROR: Binary not found in tarball"
        rm -rf "$TMP_DIR"
        return 1
    fi
}

load_binary() {
    mkdir -p "$AGH_STORAGE"

    if [ ! -f "$AGH_BIN" ]; then
        log "Binary not found, downloading..."
        download_agh || {
            log "ERROR: Cannot get AGH binary, aborting"
            nvram set adg_enable=0
            return 1
        }
    else
        log "Binary located: $AGH_BIN"
        # Chỉ chạy tiến trình update ngầm khi AGH thực sự đang chạy sau 60s
        ( sleep 60 && [ "$(nvram get adg_enable)" = "1" ] && download_agh ) &
    fi
    return 0
}

getconfig() {
    mkdir -p "$AGH_STORAGE"

    if [ ! -f "$AGH_CFG" ] || [ ! -s "$AGH_CFG" ]; then
        log "No config found, AGH will auto-generate on first run"
        return
    fi

    mkdir -p /tmp/adguard-log

    # Ép buộc chuyển Stats về RAM và giới hạn lưu trữ tối đa 24 giờ để tránh tràn RAM (/tmp)
    if grep -q '^statistics:' "$AGH_CFG"; then
        sed -i '/^statistics:/,/^[a-z]/{s|dir_path:.*|dir_path: "/tmp/adguard-log"|}' "$AGH_CFG"
        sed -i '/^statistics:/,/^[a-z]/{s|interval:.*|interval: 24h|}' "$AGH_CFG"
        log "Statistics dir set to RAM (/tmp/adguard-log, interval: 24h)"
    fi
    
    # Ép buộc chuyển Query Log về RAM và giới hạn lưu trữ tối đa 24 giờ
    if grep -q '^querylog:' "$AGH_CFG"; then
        sed -i '/^querylog:/,/^[a-z]/{s|dir_path:.*|dir_path: "/tmp/adguard-log"|}' "$AGH_CFG"
        sed -i '/^querylog:/,/^[a-z]/{s|interval:.*|interval: 24h|}' "$AGH_CFG"
        log "Querylog dir set to RAM (/tmp/adguard-log, interval: 24h)"
    fi

    rm -f "$AGH_STORAGE/data/stats.db"
    sed -i 's/  file_enabled: true/  file_enabled: false/' "$AGH_CFG"

    log "Config patched: stats→RAM, querylog→memory"
}

start_adg() {
    if pgrep AdGuardHome >/dev/null 2>&1; then
        log "Already running, skipping start"
        return
    fi

    load_binary || return 1
    getconfig

    export SSL_CERT_FILE=/etc_ro/ca-certificates.crt

    log "Starting AdGuardHome..."
    if [ -f "$AGH_CFG" ] && [ -s "$AGH_CFG" ]; then
        "$AGH_BIN" -c "$AGH_CFG" -w "$AGH_STORAGE" --no-check-update &
        log "AdGuardHome started with config (PID: $!)"
    else
        "$AGH_BIN" -w "$AGH_STORAGE" --no-check-update &
        log "AdGuardHome started in setup mode port 3000 (PID: $!)"
    fi

    local mode="$(nvram get adg_redirect)"
    if [ "$mode" = "2" ]; then
        log "Waiting for AGH to bind port 53..."
        local retry=0
        while [ $retry -lt 10 ]; do
            if netstat -tlnp 2>/dev/null | grep -q ":53 " && \
               netstat -ulnp 2>/dev/null | grep -q ":53 "; then
                log "AGH bound port 53 OK, now disabling dnsmasq DNS"
                change_dns
                break
            fi
            sleep 1
            retry=$((retry + 1))
        done
        if [ $retry -eq 10 ]; then
            log "WARNING: AGH did not bind port 53 after 10s"
            change_dns
        fi
    else
        change_dns
    fi
    set_iptable
}

stop_adg() {
    log "Stopping AdGuardHome..."

    # Kill các tiến trình adguardhome.sh khác đang chạy ngầm (tránh bị kẹt update ngầm)
    local PID_SELF=$$
    for pid in $(pgrep -f "adguardhome.sh"); do
        if [ "$pid" != "$PID_SELF" ]; then
            kill -9 "$pid" 2>/dev/null
        fi
    done

    killall -9 AdGuardHome 2>/dev/null
    del_dns
    clear_iptable
    rm -f "$AGH_STORAGE"/*.pid 2>/dev/null
    log "AdGuardHome stopped"
}

update_adg() {
    log "Checking for AGH update..."
    download_agh && {
        if pgrep AdGuardHome >/dev/null 2>&1; then
            log "Restarting AGH after update..."
            stop_adg
            sleep 1
            start_adg
        fi
    }
}

case $1 in
    start)   start_adg ;;
    stop)    stop_adg ;;
    restart) stop_adg; sleep 1; start_adg ;;
    update)  update_adg ;;
    status)
        if pgrep AdGuardHome >/dev/null 2>&1; then
            VER="$(cat $AGH_VERSION_FILE 2>/dev/null || echo unknown)"
            echo "AdGuardHome is running ($VER)"
        else
            echo "AdGuardHome is stopped"
        fi
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|update|status}"
        ;;
esac
