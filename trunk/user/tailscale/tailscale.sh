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

TS_STORAGE="/etc/storage/tailscale"   # JFFS2 - lưu state/config
TS_STATE="$TS_STORAGE/tailscaled.state"
TS_SRC="/usr/sbin/tailscaled"         # squashfs - combined binary từ build
TS_RUN="/tmp/tailscale"               # RAM - copy lúc boot
TS_BIN="$TS_RUN/tailscale"           # symlink → tailscaled
TS_DAEMON="$TS_RUN/tailscaled"       # combined binary (tailscale+tailscaled)
TS_SOCK="/tmp/tailscaled.sock"
TS_LOCK="/var/run/tailscale.lock"
TS_PID="/var/run/tailscaled.pid"

log() { logger -t "Tailscale" "$1"; }

get_nvram() { nvram get "$1"; }

# ================================================================
# Setup binary: copy từ squashfs (/usr/sbin/) → RAM (/tmp/tailscale/)
# ================================================================
setup_binary() {
    mkdir -p "$TS_STORAGE"
    mkdir -p "$TS_RUN"

    # Kiểm tra binary trong squashfs
    if [ ! -x "$TS_SRC" ]; then
        log "ERROR: Binary not found in firmware (/usr/sbin/tailscaled)"
        return 1
    fi

    # Copy combined binary sang RAM
    cp "$TS_SRC" "$TS_DAEMON"
    chmod +x "$TS_DAEMON"

    # Tạo symlink tailscale → tailscaled
    ln -sf tailscaled "$TS_BIN"

    log "Binary copied to RAM: $TS_RUN"
    return 0
}

# ================================================================
# Setup kernel modules và IP forwarding
# ================================================================
setup_system() {
    # TUN device
    mkdir -p /dev/net
    [ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200
    chmod 666 /dev/net/tun

    # Load TUN module
    modprobe tun 2>/dev/null

    # IP forwarding
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

    # State dir phải trong NAND để persist login
    "$TS_DAEMON" \
        --state="$TS_STATE" \
        --socket="$TS_SOCK" \
        --outbound-http-proxy-listen="" \
        --port=41641 \
        2>/tmp/tailscaled.log &

    echo $! > "$TS_PID"
    log "tailscaled started (PID: $!)"

    # Chờ socket ready
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
# Connect/Login tailscale
# ================================================================
connect_tailscale() {
    local AUTHKEY="$(get_nvram ts_authkey)"
    local HOSTNAME="$(get_nvram ts_hostname)"
    local EXITNODE="$(get_nvram ts_exitnode)"
    local SUBNET="$(get_nvram ts_subnet)"
    local ACCEPT="$(get_nvram ts_accept_routes)"
    local ALLOW_LAN="$(get_nvram ts_allow_lan)"
    local SHIELDS="$(get_nvram ts_shields_up)"

    local ARGS="--reset"

    # Auth key (one-time login)
    [ -n "$AUTHKEY" ] && ARGS="$ARGS --authkey=$AUTHKEY"

    # Hostname
    [ -n "$HOSTNAME" ] && ARGS="$ARGS --hostname=$HOSTNAME"

    # Exit node
    [ "$EXITNODE" = "1" ] && ARGS="$ARGS --advertise-exit-node"

    # Subnet routing
    [ -n "$SUBNET" ] && ARGS="$ARGS --advertise-routes=$SUBNET"

    # Accept routes
    [ "$ACCEPT" = "1" ] && ARGS="$ARGS --accept-routes" || ARGS="$ARGS --accept-routes=false"

    # Allow LAN khi dùng exit node
    [ "$ALLOW_LAN" = "1" ] && ARGS="$ARGS --exit-node-allow-lan-access"

    # Shields up
    [ "$SHIELDS" = "1" ] && ARGS="$ARGS --shields-up"

    log "Connecting: tailscale up $ARGS"
    "$TS_BIN" --socket="$TS_SOCK" up $ARGS

    if [ $? -eq 0 ]; then
        log "Tailscale connected OK"
        
        # Đọc IP và Version trực tiếp từ daemon và lưu vào NVRAM tạm (trên RAM)
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

    # Logout giữ state
    if [ -S "$TS_SOCK" ] && [ -x "$TS_BIN" ]; then
        "$TS_BIN" --socket="$TS_SOCK" down 2>/dev/null
    fi

    # Kill daemon
    if [ -f "$TS_PID" ]; then
        kill "$(cat $TS_PID)" 2>/dev/null
        rm -f "$TS_PID"
    fi
    pkill tailscaled 2>/dev/null
    pkill tailscale  2>/dev/null

    # Cleanup RAM
    rm -rf "$TS_RUN"
    rm -f "$TS_SOCK" "$TS_LOCK"

    # Reset trạng thái đã dừng cho WebUI đọc nhanh
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

# ================================================================
# Get Tailscale IP (cho WebUI)
# ================================================================
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

    # Set trạng thái kết nối trung gian lúc bắt đầu
    nvram set ts_status="connecting"
    nvram set ts_ip="--"

    # Copy binary từ squashfs sang RAM
    setup_binary || { rm -f "$TS_LOCK"; return 1; }

    # Setup system
    setup_system

    # Start daemon
    start_daemon || { rm -f "$TS_LOCK"; return 1; }

    # Connect
    connect_tailscale

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
