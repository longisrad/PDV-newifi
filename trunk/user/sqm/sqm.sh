#!/bin/sh
#
# SQM QoS script - HTB + fq_codel
# Config stored in NVRAM:
#   sqm_enable   : 0/1
#   sqm_iface    : WAN interface (e.g. eth3, apclii0)
#   sqm_down     : download kbps
#   sqm_up       : upload kbps
#   sqm_qdisc    : fq_codel or cake
#   sqm_overhead : overhead bytes (0 = none, WiFi = 30)
#   sqm_preset   : none|gaming|streaming|wfh|balanced|custom
#   sqm_game_ports: UDP port ranges cho preset custom (comma-separated)
#

SQM_LOCK="/var/run/sqm.lock"

get_nvram() { nvram get "$1"; }
log() { logger -t "SQM" "$1"; }

# ================================================================
# PRESET DEFINITIONS
# ================================================================
# Mỗi preset định nghĩa:
#   - ECN on/off
#   - DSCP class rules (EF=high, AF41=medium-high, AF31=medium, CS1=low)
#   - iptables port marks

# Helper: mark 1 port range cả POSTROUTING lẫn PREROUTING
_mark() {
    local IFACE="$1" PROTO="$2" DIR="$3" PORT="$4" DSCP="$5"
    if [ "$DIR" = "dport" ]; then
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p "$PROTO" --dport "$PORT" -j DSCP --set-dscp-class "$DSCP" 2>/dev/null
        iptables -t mangle -A PREROUTING  -i "$IFACE" -p "$PROTO" --sport "$PORT" -j DSCP --set-dscp-class "$DSCP" 2>/dev/null
    else
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p "$PROTO" --sport "$PORT" -j DSCP --set-dscp-class "$DSCP" 2>/dev/null
        iptables -t mangle -A PREROUTING  -i "$IFACE" -p "$PROTO" --dport "$PORT" -j DSCP --set-dscp-class "$DSCP" 2>/dev/null
    fi
}

# Helper: hạ bulk TCP khi connection vượt threshold bytes → CS1
_bulk_throttle() {
    local IFACE="$1" BYTES="$2"
    iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp -m connbytes \
        --connbytes "$BYTES": --connbytes-dir both --connbytes-mode bytes \
        -j DSCP --set-dscp-class CS1 2>/dev/null
    iptables -t mangle -A PREROUTING -i "$IFACE" -p tcp -m connbytes \
        --connbytes "$BYTES": --connbytes-dir both --connbytes-mode bytes \
        -j DSCP --set-dscp-class CS1 2>/dev/null
}

apply_preset_filters() {
    local IFACE="$1"
    local PRESET="$2"
    local CUSTOM_PORTS="$3"

    case "$PRESET" in

    gaming)
        log "Preset: Gaming"
        # ── EF (cao nhất): game UDP realtime ──────────────────────────
        # Liên Quân Mobile
        _mark "$IFACE" udp dport 5000:5060  EF
        _mark "$IFACE" udp dport 8001:8002  EF
        # PUBG Mobile / PUBG PC
        _mark "$IFACE" udp dport 10012:10012 EF
        _mark "$IFACE" udp dport 10006:10006 EF
        # Steam / DOTA2 / CS2
        _mark "$IFACE" udp dport 27015:27030 EF
        _mark "$IFACE" udp dport 27000:27015 EF
        # Xbox Live / Call of Duty
        _mark "$IFACE" udp dport 3074:3074   EF
        _mark "$IFACE" udp dport 3075:3076   EF
        # Garena (Free Fire, LOL VN)
        _mark "$IFACE" udp dport 5222:5223   EF
        _mark "$IFACE" udp dport 7000:7001   EF
        # Valorant
        _mark "$IFACE" udp dport 7086:7086   EF
        _mark "$IFACE" udp dport 7500:8099   EF
        # Minecraft
        _mark "$IFACE" udp dport 19132:19133 EF
        # DNS (quan trọng cho game matchmaking)
        _mark "$IFACE" udp dport 53:53       EF
        _mark "$IFACE" tcp dport 53:53       EF
        # ── CS1 (thấp): bulk download lớn ─────────────────────────────
        _bulk_throttle "$IFACE" 2000000
        ;;

    streaming)
        log "Preset: Streaming"
        # ── AF41 (medium-high): video stream ──────────────────────────
        # HTTPS/QUIC (YouTube, Netflix, TikTok, Twitch, Disney+)
        _mark "$IFACE" tcp dport 443  AF41
        _mark "$IFACE" udp dport 443  AF41
        # HTTP fallback
        _mark "$IFACE" tcp dport 80   AF41
        # RTMP (OBS stream lên YouTube/Twitch)
        _mark "$IFACE" tcp dport 1935 AF41
        _mark "$IFACE" tcp dport 1936 AF41
        # RTSP (camera, IPTV)
        _mark "$IFACE" tcp dport 554  AF41
        _mark "$IFACE" udp dport 554  AF41
        # RTP/RTCP media (IPTV, VoIP media)
        _mark "$IFACE" udp dport 5004:5005 AF41
        # DNS ưu tiên (tránh buffer khi start stream)
        _mark "$IFACE" udp dport 53   AF41
        # ── CS1 (thấp): bulk sau khi đã đủ buffer ─────────────────────
        _bulk_throttle "$IFACE" 5000000
        ;;

    wfh)
        log "Preset: Work From Home"
        # ── EF (cao nhất): VoIP/Video call realtime ───────────────────
        # Zoom UDP
        _mark "$IFACE" udp dport 3478:3479  EF
        _mark "$IFACE" udp dport 8801:8802  EF
        _mark "$IFACE" udp dport 8803:8803  EF
        # Google Meet / WebRTC
        _mark "$IFACE" udp dport 19302:19309 EF
        _mark "$IFACE" udp dport 3478:3481   EF
        # MS Teams UDP
        _mark "$IFACE" udp dport 50000:50059 EF
        _mark "$IFACE" udp dport 3478:3481   EF
        # Discord voice/video
        _mark "$IFACE" udp dport 50000:50050 EF
        # Zalo call
        _mark "$IFACE" udp dport 3478:3480   EF
        # DNS
        _mark "$IFACE" udp dport 53  EF
        _mark "$IFACE" tcp dport 53  EF
        # ── AF31 (medium): web/app làm việc ───────────────────────────
        _mark "$IFACE" tcp dport 443  AF31
        _mark "$IFACE" tcp dport 80   AF31
        # SSH/SFTP remote work
        _mark "$IFACE" tcp dport 22   AF31
        # ── CS1 (thấp): bulk download/upload ──────────────────────────
        _bulk_throttle "$IFACE" 2000000
        ;;

    balanced)
        log "Preset: Balanced"
        # DNS luôn ưu tiên cao
        _mark "$IFACE" udp dport 53  EF
        _mark "$IFACE" tcp dport 53  EF
        # Hạ bulk khi connection rất lớn (>10MB)
        _bulk_throttle "$IFACE" 10000000
        ;;

    custom)
        log "Preset: Custom (ports: $CUSTOM_PORTS)"
        [ -z "$CUSTOM_PORTS" ] && CUSTOM_PORTS="5000-5060,8001-8002"
        # DNS luôn ưu tiên
        _mark "$IFACE" udp dport 53  EF

        echo "$CUSTOM_PORTS" | tr ',' '\n' | while read port_range; do
            port_range="$(echo "$port_range" | tr -d ' ')"
            [ -z "$port_range" ] && continue
            if echo "$port_range" | grep -q '-'; then
                START="$(echo "$port_range" | cut -d'-' -f1)"
                END="$(echo "$port_range" | cut -d'-' -f2)"
            else
                START="$port_range"; END="$port_range"
            fi
            _mark "$IFACE" udp dport "$START:$END" EF
        done
        _bulk_throttle "$IFACE" 2000000
        ;;

    none|*)
        log "Preset: None (no priority filter)"
        ;;
    esac
}

# ================================================================
# DSCP class setup (dùng chung cho mọi preset trừ none)
# ================================================================
setup_dscp_classes() {
    local IFACE="$1"
    local UP_KBIT="$2"
    local PRESET="$3"

    [ "$PRESET" = "none" ] && return

    # Tính rate cho từng class
    local UP_NUM="${UP_KBIT%kbit}"
    local GAME_RATE=$(( UP_NUM * 15 / 100 ))kbit   # 15% guaranteed cho game
    local BULK_CEIL=$(( UP_NUM * 70 / 100 ))kbit   # bulk bị cap 70% khi contention
    local NORM_RATE=$(( UP_NUM * 80 / 100 ))kbit   # dùng cho streaming/wfh middle class

    # Class 1:20 → EF high priority: guaranteed 15%, burst tối đa 100%
    tc class add dev "$IFACE" parent 1:1 classid 1:20 htb \
        rate ${GAME_RATE} ceil "$UP_KBIT" prio 1
    tc qdisc add dev "$IFACE" parent 1:20 fq_codel ecn

    # Class 1:30 → CS1 bulk low priority: guaranteed 15%, ceil 70%
    tc class add dev "$IFACE" parent 1:1 classid 1:30 htb \
        rate ${GAME_RATE} ceil ${BULK_CEIL} prio 3
    tc qdisc add dev "$IFACE" parent 1:30 fq_codel ecn

    # Streaming/WFH có thêm class AF41 medium-high
    if [ "$PRESET" = "streaming" ] || [ "$PRESET" = "wfh" ]; then
        tc class add dev "$IFACE" parent 1:1 classid 1:25 htb \
            rate ${NORM_RATE} ceil "$UP_KBIT" prio 2
        tc qdisc add dev "$IFACE" parent 1:25 fq_codel ecn
        # AF41 (0x88) → 1:25
        tc filter add dev "$IFACE" parent 1: protocol ip prio 3 u32 \
            match ip dsfield 0x88 0xfc flowid 1:25
        # AF31 (0x68) → 1:25
        tc filter add dev "$IFACE" parent 1: protocol ip prio 4 u32 \
            match ip dsfield 0x68 0xfc flowid 1:25
    fi

    # EF (0xb8) → 1:20
    tc filter add dev "$IFACE" parent 1: protocol ip prio 1 u32 \
        match ip dsfield 0xb8 0xfc flowid 1:20

    # CS1 (0x20) → 1:30
    tc filter add dev "$IFACE" parent 1: protocol ip prio 2 u32 \
        match ip dsfield 0x20 0xfc flowid 1:30
}

stop_sqm() {
    log "Stopping SQM..."
    IFACE="$(get_nvram sqm_iface)"
    [ -z "$IFACE" ] && IFACE="eth3"

    tc qdisc del dev "$IFACE" root 2>/dev/null
    tc qdisc del dev "$IFACE" ingress 2>/dev/null
    tc qdisc del dev ifb0 root 2>/dev/null
    ip link set ifb0 down 2>/dev/null

    iptables -t mangle -F POSTROUTING 2>/dev/null
    iptables -t mangle -F PREROUTING  2>/dev/null

    rm -f "$SQM_LOCK"
    log "SQM stopped"
}

start_sqm() {
    if [ -f "$SQM_LOCK" ]; then
        log "SQM already running"
        return
    fi

    IFACE="$(get_nvram sqm_iface)"
    DOWN="$(get_nvram sqm_down)"
    UP="$(get_nvram sqm_up)"
    QDISC="$(get_nvram sqm_qdisc)"
    OVERHEAD="$(get_nvram sqm_overhead)"
    PRESET="$(get_nvram sqm_preset)"
    CUSTOM_PORTS="$(get_nvram sqm_game_ports)"

    [ -z "$IFACE" ]    && { log "ERROR: sqm_iface not set"; return 1; }
    [ -z "$DOWN" ]     && { log "ERROR: sqm_down not set"; return 1; }
    [ -z "$UP" ]       && { log "ERROR: sqm_up not set"; return 1; }
    [ -z "$QDISC" ]    && QDISC="fq_codel"
    [ -z "$OVERHEAD" ] && OVERHEAD="0"
    [ -z "$PRESET" ]   && PRESET="none"

    # ECN bật tự động cho mọi preset trừ none
    ECN_OPT=""
    [ "$PRESET" != "none" ] && ECN_OPT="ecn"

    DOWN_KBIT="${DOWN}kbit"
    UP_KBIT="${UP}kbit"

    log "Starting SQM: iface=$IFACE down=$DOWN_KBIT up=$UP_KBIT preset=$PRESET"

    modprobe sch_htb      2>/dev/null
    modprobe sch_fq_codel 2>/dev/null
    modprobe ifb          2>/dev/null
    modprobe act_mirred   2>/dev/null
    modprobe xt_DSCP      2>/dev/null
    modprobe xt_connbytes 2>/dev/null

    # -------------------------
    # EGRESS (upload)
    # -------------------------
    tc qdisc del dev "$IFACE" root 2>/dev/null
    tc qdisc add dev "$IFACE" root handle 1: htb default 10
    tc class add dev "$IFACE" parent 1:  classid 1:1  htb rate "$UP_KBIT" ceil "$UP_KBIT"
    tc class add dev "$IFACE" parent 1:1 classid 1:10 htb rate "$UP_KBIT" ceil "$UP_KBIT" prio 2

    if [ "$QDISC" = "cake" ]; then
        tc qdisc add dev "$IFACE" parent 1:10 cake bandwidth "$UP_KBIT" overhead "$OVERHEAD" $ECN_OPT 2>/dev/null \
            || tc qdisc add dev "$IFACE" parent 1:10 fq_codel $ECN_OPT
    else
        tc qdisc add dev "$IFACE" parent 1:10 fq_codel $ECN_OPT
    fi

    # Setup DSCP classes + filters
    setup_dscp_classes "$IFACE" "$UP_KBIT" "$PRESET"

    # Apply preset iptables marks
    apply_preset_filters "$IFACE" "$PRESET" "$CUSTOM_PORTS"

    # -------------------------
    # INGRESS (download via IFB)
    # -------------------------
    ip link set ifb0 up 2>/dev/null
    tc qdisc del dev "$IFACE" ingress 2>/dev/null
    tc qdisc add dev "$IFACE" ingress
    tc filter add dev "$IFACE" parent ffff: protocol all u32 \
        match u32 0 0 action mirred egress redirect dev ifb0

    tc qdisc del dev ifb0 root 2>/dev/null
    tc qdisc add dev ifb0 root handle 1: htb default 10
    tc class add dev ifb0 parent 1:  classid 1:1  htb rate "$DOWN_KBIT" ceil "$DOWN_KBIT"
    tc class add dev ifb0 parent 1:1 classid 1:10 htb rate "$DOWN_KBIT" ceil "$DOWN_KBIT"

    if [ "$QDISC" = "cake" ]; then
        tc qdisc add dev ifb0 parent 1:10 cake bandwidth "$DOWN_KBIT" overhead "$OVERHEAD" $ECN_OPT 2>/dev/null \
            || tc qdisc add dev ifb0 parent 1:10 fq_codel $ECN_OPT
    else
        tc qdisc add dev ifb0 parent 1:10 fq_codel $ECN_OPT
    fi

    touch "$SQM_LOCK"
    log "SQM started (preset: $PRESET)"
}

status_sqm() {
    IFACE="$(get_nvram sqm_iface)"
    PRESET="$(get_nvram sqm_preset)"
    echo "=== SQM Status (preset: $PRESET) ==="
    echo ""
    echo "--- Egress (upload) ---"
    tc class show dev "$IFACE" 2>/dev/null
    echo ""
    echo "--- Ingress/IFB (download) ---"
    tc qdisc show dev ifb0 2>/dev/null
    echo ""
    echo "--- DSCP Filters ---"
    iptables -t mangle -L POSTROUTING -n 2>/dev/null | grep -E "DSCP|dscp"
}

case "$1" in
    start)   [ "$(get_nvram sqm_enable)" = "1" ] && start_sqm ;;
    stop)    stop_sqm ;;
    restart) stop_sqm; sleep 1; [ "$(get_nvram sqm_enable)" = "1" ] && start_sqm ;;
    status)  status_sqm ;;
    *)       echo "Usage: $0 {start|stop|restart|status}" ;;
esac
