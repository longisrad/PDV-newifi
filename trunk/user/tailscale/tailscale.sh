#!/bin/sh
#
# Tailscale for Padavan (MT7621/MIPS)
# Binary lưu NAND: /etc/storage/tailscale/
# Chạy trên RAM: /tmp/tailscale/
#
# NVRAM keys:
#   ts_enable      : 0/1
#   ts_authkey     : auth key (one-time, xóa sau login)
#   ts_hostname    : custom hostname
#   ts_exitnode    : 0/1 advertise exit node
#   ts_subnet      : subnet để advertise (e.g. 192.168.123.0/24)
#   ts_accept_routes: 0/1 accept routes from other nodes
#   ts_allow_lan   : 0/1 allow LAN access when using exit node
#   ts_shields_up  : 0/1 block incoming connections
#

TS_STORAGE="/etc/storage/tailscale"
TS_STATE="$TS_STORAGE/tailscaled.state"
TS_SRC="/usr/sbin/tailscaled"
TS_RUN="/tmp/tailscale"
TS_BIN="$TS_RUN/tailscale"
TS_DAEMON="$TS_RUN/tailscaled"
TS_SOCK="/tmp/tailscaled.sock"
TS_LOCK="/var/run/tailscale.lock"
TS_PID="/var/run/tailscaled.pid"
TS_WATCHDOG_PID="/var/run/tailscale_watchdog.pid"

log() { logger -t "Tailscale" "$1"; }
get_nvram() { nvram get "$1"; }

# ================================================================
# Setup binary
# ================================================================
setup_binary() {
    mkdir -p "$TS_STORAGE"
    mkdir -p "$TS_RUN"

    if [ ! -x "$TS_SRC" ]; then
        log "ERROR: Binary not found in firmware (/usr/sbin/tailscaled)"
        return 1
    fi

    cp "$TS_SRC" "$TS_DAEMON"
    chmod +x "$TS_DAEMON"
    ln -sf tailscaled "$TS_BIN"

    log "Binary copied to RAM: $TS_RUN"
    return 0
}

# ================================================================
# Setup kernel modules và IP forwarding
# ================================================================
setup_system() {
    mkdir -p /dev/net
    [ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200
    chmod 666 /dev/net/tun
    modprobe tun 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null
    log "System setup OK (TUN, ip_forward)"
}

# ================================================================
# Start tailscaled daemon
# ================================================================
start_daemon() {
    if pgrep tailscaled >/dev/null 2>&1; then
        log "tailscaled already running"
        return 0
    fi

    mkdir -p "$TS_RUN"

    "$TS_DAEMON" \
        --state="$TS_STATE" \
        --socket="$TS_SOCK" \
        --outbound-http-proxy-listen="" \
        --port=41641 \
        2>/tmp/tailscaled.log &

    echo $! > "$TS_PID"
    log "tailscaled started (PID: $!)"

    local retry=0
    while [ $retry -lt 15 ]; do
        [ -S "$TS_SOCK" ] && break
        sleep 1
        retry=$((retry + 1))
    done

    if [ ! -S "$TS_SOCK" ]; then
        log "ERROR: tailscaled socket not ready after 15s"
        return 1
    fi

    log "tailscaled socket ready"
    return 0
}

# ================================================================
# Watchdog: tự restart nếu tailscaled crash
# ================================================================
start_watchdog() {
    # Kill watchdog cũ nếu có
    if [ -f "$TS_WATCHDOG_PID" ]; then
        kill "$(cat $TS_WATCHDOG_PID)" 2>/dev/null
        rm -f "$TS_WATCHDOG_PID"
    fi

    (
        while true; do
            sleep 30
            # Chỉ watchdog khi ts_enable=1
            [ "$(get_nvram ts_enable)" != "1" ] && break
            if ! pgrep tailscaled >/dev/null 2>&1; then
                log "Watchdog: tailscaled crashed, restarting..."
                setup_binary && start_daemon && connect_tailscale
            fi
        done
    ) &
    echo $! > "$TS_WATCHDOG_PID"
    log "Watchdog started (PID: $!)"
}

# ================================================================
# Connect/Login tailscale
# ================================================================
connect_tailscale() {
    # Nếu đã có state file → đã login rồi, không cần authkey
    # Nếu chưa có state → chờ NVRAM commit xong tối đa 10s
    local AUTHKEY=""
    if [ ! -f "$TS_STATE" ]; then
        local retry=0
        while [ $retry -lt 10 ]; do
            AUTHKEY="$(get_nvram ts_authkey)"
            [ -n "$AUTHKEY" ] && break
            sleep 1
            retry=$((retry + 1))
        done
        [ -z "$AUTHKEY" ] && log "Warning: no authkey found after 10s wait"
    fi

    local HOSTNAME="$(get_nvram ts_hostname)"
    local EXITNODE="$(get_nvram ts_exitnode)"
    local SUBNET="$(get_nvram ts_subnet)"
    local ACCEPT="$(get_nvram ts_accept_routes)"
    local ALLOW_LAN="$(get_nvram ts_allow_lan)"
    local SHIELDS="$(get_nvram ts_shields_up)"

    # Dùng --reset chỉ khi có authkey (login lần đầu)
    # Restart bình thường không --reset để giữ config
    local ARGS=""
    [ -n "$AUTHKEY" ] && ARGS="--reset --authkey=$AUTHKEY" || ARGS=""

    [ -n "$HOSTNAME" ]   && ARGS="$ARGS --hostname=$HOSTNAME"
    [ "$EXITNODE" = "1" ] && ARGS="$ARGS --advertise-exit-node"
    [ -n "$SUBNET" ]     && ARGS="$ARGS --advertise-routes=$SUBNET"
    [ "$ACCEPT" = "1" ]  && ARGS="$ARGS --accept-routes" || ARGS="$ARGS --accept-routes=false"
    [ "$ALLOW_LAN" = "1" ] && ARGS="$ARGS --exit-node-allow-lan-access"
    [ "$SHIELDS" = "1" ] && ARGS="$ARGS --shields-up"

    log "Connecting: tailscale up $ARGS"
    "$TS_BIN" --socket="$TS_SOCK" up $ARGS

    if [ $? -eq 0 ]; then
        log "Tailscale connected OK"

        local IP="$("$TS_BIN" --socket="$TS_SOCK" ip 2>/dev/null | head -1)"
        local VER="$("$TS_DAEMON" --version 2>/dev/null | head -1)"

        [ -z "$IP" ] && IP="--"
        [ -z "$VER" ] && VER="unknown"

        nvram set ts_status="running"
        nvram set ts_ip="$IP"
        nvram set ts_version="$VER"

        # Xóa authkey sau khi login thành công
        if [ -n "$AUTHKEY" ]; then
            nvram unset ts_authkey
            nvram commit
            log "Auth key cleared from nvram"
        fi
    else
        log "ERROR: tailscale up failed"
        nvram set ts_status="failed"
        nvram set ts_ip="--"
        return 1
    fi
}

# ================================================================
# Stop
# ================================================================
stop_tailscale() {
    log "Stopping Tailscale..."

    # Stop watchdog trước
    if [ -f "$TS_WATCHDOG_PID" ]; then
        kill "$(cat $TS_WATCHDOG_PID)" 2>/dev/null
        rm -f "$TS_WATCHDOG_PID"
    fi

    if [ -S "$TS_SOCK" ] && [ -x "$TS_BIN" ]; then
        "$TS_BIN" --socket="$TS_SOCK" down 2>/dev/null
    fi

    if [ -f "$TS_PID" ]; then
        kill "$(cat $TS_PID)" 2>/dev/null
        rm -f "$TS_PID"
    fi
    pkill tailscaled 2>/dev/null
    pkill tailscale  2>/dev/null

    # Xóa jump rules vào ts chains tránh DROP khi chain không còn
    iptables -D INPUT -j ts-input 2>/dev/null
    iptables -D FORWARD -j ts-forward 2>/dev/null

    rm -rf "$TS_RUN"
    rm -f "$TS_SOCK" "$TS_LOCK"

    nvram set ts_status="stopped"
    nvram set ts_ip="--"

    log "Tailscale stopped"
}

# ================================================================
# Status
# ================================================================
status_tailscale() {
    if ! pgrep tailscaled >/dev/null 2>&1; then
        echo "Status: stopped"
        return 1
    fi

    if [ ! -S "$TS_SOCK" ]; then
        echo "Status: daemon running but socket missing"
        return 1
    fi

    "$TS_BIN" --socket="$TS_SOCK" status 2>/dev/null
}

get_ip() {
    "$TS_BIN" --socket="$TS_SOCK" ip 2>/dev/null | head -1
}

# ================================================================
# Main
# ================================================================
start_tailscale() {
    if [ -f "$TS_LOCK" ]; then
        log "Already running"
        return
    fi
    touch "$TS_LOCK"

    nvram set ts_status="connecting"
    nvram set ts_ip="--"

    setup_binary || { rm -f "$TS_LOCK"; return 1; }
    setup_system
    start_daemon || { rm -f "$TS_LOCK"; return 1; }
    connect_tailscale
    start_watchdog

    log "Tailscale start complete"
}

case "$1" in
    start)
        [ "$(get_nvram ts_enable)" = "1" ] && start_tailscale
        ;;
    stop)
        stop_tailscale
        ;;
    restart)
        stop_tailscale
        sleep 1
        [ "$(get_nvram ts_enable)" = "1" ] && start_tailscale
        ;;
    status)
        status_tailscale
        ;;
    ip)
        get_ip
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|ip}"
        ;;
esac
