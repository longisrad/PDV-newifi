#!/bin/sh
#
# Tailscale cho Padavan - Tự động tải và lưu vào NAND
#

TS_STORAGE="/etc/storage/tailscale"      # Nơi lưu trữ persistent (NAND hoặc USB)
TS_BIN_NAND="$TS_STORAGE/tailscaled"     # File binary gốc
TS_RUN="/tmp/tailscale"                  # Chạy trên RAM
TS_DAEMON="$TS_RUN/tailscaled"           # Binary copy vào RAM để chạy
TS_BIN="$TS_RUN/tailscale"               # Symlink
TS_SOCK="/tmp/tailscaled.sock"
TS_PID="/var/run/tailscaled.pid"
TS_LOCK="/var/run/tailscale.lock"

# Link tải binary (MIPSLE Softfloat cho MT7621)
# Sử dụng bản nén hoặc bản full tùy ý. Ở đây dùng bản từ repo lmq8267
TS_URL="https://github.com/lmq8267/tailscale/releases/latest/download/tailscaled_full"

log() { logger -t "Tailscale" "$1"; }
get_nvram() { nvram get "$1"; }

setup_binary() {
    mkdir -p "$TS_STORAGE"
    mkdir -p "$TS_RUN"

    # 1. Kiểm tra nếu binary chưa có ở NAND thì tải về
    if [ ! -f "$TS_BIN_NAND" ] || [ ! -s "$TS_BIN_NAND" ]; then
        log "Binary not found in storage. Downloading from GitHub..."
        
        # Thử tải bằng wget (cần có CA-Certificates để tải HTTPS)
        wget --no-check-certificate -O "$TS_BIN_NAND.tmp" "$TS_URL"
        
        if [ $? -eq 0 ] && [ -s "$TS_BIN_NAND.tmp" ]; then
            mv "$TS_BIN_NAND.tmp" "$TS_BIN_NAND"
            chmod +x "$TS_BIN_NAND"
            log "Download successful."
            # Lưu lại vào flash (mtd_storage.sh save) nếu dùng /etc/storage
            [ "/etc/storage" == "$(dirname $(dirname $TS_BIN_NAND))" ] && /sbin/mtd_storage.sh save
        else
            log "ERROR: Download failed. Check internet connection or storage space."
            rm -f "$TS_BIN_NAND.tmp"
            return 1
        fi
    fi

    # 2. Copy từ NAND sang RAM để chạy (tránh ghi hỏng flash/NAND liên tục)
    cp "$TS_BIN_NAND" "$TS_DAEMON"
    chmod +x "$TS_DAEMON"
    ln -sf tailscaled "$TS_BIN"

    log "Binary loaded to RAM."
    return 0
}

setup_system() {
    mkdir -p /dev/net
    [ ! -c /dev/net/tun ] && mknod /dev/net/tun c 10 200
    chmod 666 /dev/net/tun
    modprobe tun 2>/dev/null
    echo 1 > /proc/sys/net/ipv4/ip_forward
    echo 1 > /proc/sys/net/ipv6/conf/all/forwarding 2>/dev/null
}

start_daemon() {
    if pgrep tailscaled >/dev/null 2>&1; then return 0; fi

    # Sử dụng file state trong NAND để giữ login sau reboot
    "$TS_DAEMON" \
        --state="$TS_STORAGE/tailscaled.state" \
        --socket="$TS_SOCK" \
        --port=41641 \
        2>/tmp/tailscaled.log &

    echo $! > "$TS_PID"
    
    # Chờ socket
    local retry=0
    while [ $retry -lt 15 ]; do
        [ -S "$TS_SOCK" ] && break
        sleep 1
        retry=$((retry + 1))
    done
    return 0
}

connect_tailscale() {
    local AUTHKEY="$(get_nvram ts_authkey)"
    local ARGS="--reset"
    
    [ -n "$AUTHKEY" ] && ARGS="$ARGS --authkey=$AUTHKEY"
    [ "$(get_nvram ts_exitnode)" = "1" ] && ARGS="$ARGS --advertise-exit-node"
    [ -n "$(get_nvram ts_subnet)" ] && ARGS="$ARGS --advertise-routes=$(get_nvram ts_subnet)"
    [ "$(get_nvram ts_accept_routes)" = "1" ] && ARGS="$ARGS --accept-routes"

    "$TS_BIN" --socket="$TS_SOCK" up $ARGS
    if [ $? -eq 0 ]; then
        log "Tailscale connected."
        [ -n "$AUTHKEY" ] && { nvram unset ts_authkey; nvram commit; }
    fi
}

# ... các hàm stop/status giữ nguyên như file cũ ...

case "$1" in
    start)
        if [ "$(get_nvram ts_enable)" = "1" ]; then
            setup_binary && setup_system && start_daemon && connect_tailscale
        fi
        ;;
    stop)
        # Kill và dọn dẹp RAM
        pkill tailscaled
        rm -rf "$TS_RUN"
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        ;;
esac