#!/bin/sh
# /usr/bin/tailscale.sh
# Kịch bản quản lý Tailscale giải nén trực tiếp từ Flash ra RAM

BIN_DIR="/tmp/tailscale"
BIN_PATH="$BIN_DIR/tailscaled"
SOCKET_PATH="/var/run/tailscale/tailscaled.sock"
STATE_PATH="/etc/storage/tailscale/tailscaled.state"

extract_tailscale() {
    logger -t "Tailscale" "Bắt đầu giải nén từ bộ nhớ Flash (/etc_ro)..."
    mkdir -p "$BIN_DIR"
    mkdir -p "/var/run/tailscale"
    mkdir -p "/etc/storage/tailscale"
    
    # Giải nén tệp tar.gz được đóng gói sẵn trong ROM
    if [ -f "/etc_ro/tailscale.tar.gz" ]; then
        tar -zxf /etc_ro/tailscale.tar.gz -C "$BIN_DIR/"
        
        # Đổi tên tệp sau khi giải nén cho đúng định dạng
        if [ -f "$BIN_DIR/tailscaled" ]; then
            chmod +x "$BIN_PATH"
            # Tạo liên kết để sử dụng được CLI 'tailscale'
            ln -sf "$BIN_PATH" "$BIN_DIR/tailscale"
            logger -t "Tailscale" "Giải nén thành công ra RAM!"
            return 0
        fi
    fi
    logger -t "Tailscale" "LỖI: Không tìm thấy file nén trong bộ nhớ Flash!"
    return 1
}

start_tailscale() {
    logger -t "Tailscale" "Đang khởi động dịch vụ..."
    
    # Nếu file chạy chưa có trên RAM, tiến hành giải nén từ Flash
    if [ ! -f "$BIN_PATH" ]; then
        extract_tailscale
        if [ $? -ne 0 ]; then
            return 1
        fi
    fi

    # Đọc cấu hình được người dùng thiết lập từ NVRAM
    ACCEPT_DNS=$( [ "$(nvram get tailscale_accept_dns)" = "1" ] && echo "true" || echo "false" )
    ACCEPT_ROUTES=$( [ "$(nvram get tailscale_accept_routes)" = "1" ] && echo "true" || echo "false" )
    SUBNETS="$(nvram get tailscale_subnets)"
    EXITNODE="$(nvram get tailscale_exitnode)"
    CUSTOM_ARGS="$(nvram get tailscale_args)"

    ARGS="--accept-dns=$ACCEPT_DNS --accept-routes=$ACCEPT_ROUTES"

    if [ -n "$SUBNETS" ]; then
        ARGS="$ARGS --advertise-routes=$SUBNETS"
    fi

    if [ "$EXITNODE" = "1" ]; then
        ARGS="$ARGS --advertise-exit-node"
    fi

    if [ -n "$CUSTOM_ARGS" ]; then
        ARGS="$ARGS $CUSTOM_ARGS"
    fi

    # Khởi chạy Daemon tailscaled ngầm
    if ! pidof tailscaled > /dev/null; then
        "$BIN_PATH" --state="$STATE_PATH" --socket="$SOCKET_PATH" > /dev/null 2>&1 &
        sleep 4
    fi

    # Khởi chạy giao diện Web chính chủ trên cổng 8989 và kết nối mạng
    if pidof tailscaled > /dev/null; then
        "$BIN_DIR/tailscale" --socket="$SOCKET_PATH" web --listen 0.0.0.0:8989 > /dev/null 2>&1 &
        "$BIN_DIR/tailscale" --socket="$SOCKET_PATH" up $ARGS > /dev/null 2>&1 &
        logger -t "Tailscale" "Dịch vụ đã được kích hoạt thành công."
    else
        logger -t "Tailscale" "LỖI: Không thể khởi chạy tiến trình tailscaled."
    fi
}

stop_tailscale() {
    logger -t "Tailscale" "Đang dừng dịch vụ và giải phóng RAM..."
    killall tailscaled tailscale 2>/dev/null
    rm -rf "$BIN_DIR"
    rm -rf "/var/run/tailscale"
    logger -t "Tailscale" "Đã giải phóng tài nguyên hệ thống hoàn toàn."
}

case "$1" in
    start)
        start_tailscale
        ;;
    stop)
        stop_tailscale
        ;;
    restart)
        stop_tailscale
        sleep 2
        start_tailscale
        ;;
    *)
        echo "Sử dụng: $0 {start|stop|restart}"
        ;;
esac
