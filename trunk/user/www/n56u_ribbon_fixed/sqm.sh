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

apply_preset_filters() {
    local IFACE="$1"
    local PRESET="$2"
    local CUSTOM_PORTS="$3"

    case "$PRESET" in

    gaming)
        # Ưu tiên: Game UDP > default > Bulk download
        # EF  (0xb8): game UDP
        # CS1 (0x20): bulk (torrent, HTTP download lớn)
        log "Preset: Gaming"

        # Mark game UDP → EF
        for ports in "5000:5060" "8001:8002" "10012:10012" "27015:27030" "3074:3074"; do
            START="${ports%:*}"; END="${ports#*:}"
            iptables -t mangle -A POSTROUTING -o "$IFACE" -p udp --dport "$START:$END" -j DSCP --set-dscp-class EF 2>/dev/null
            iptables -t mangle -A PREROUTING  -i "$IFACE" -p udp --sport "$START:$END" -j DSCP --set-dscp-class EF 2>/dev/null
        done

        # Mark bulk (HTTP large, BitTorrent) → CS1
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp -m connbytes \
            --connbytes 1000000: --connbytes-dir both --connbytes-mode bytes \
            -j DSCP --set-dscp-class CS1 2>/dev/null
        ;;

    streaming)
        # Ưu tiên: Streaming video > default > Bulk
        # AF41 (0x88): video streaming
        # CS1  (0x20): bulk
        log "Preset: Streaming"

        # HTTPS streaming (Netflix, YouTube, Disney+)
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp --dport 443 -j DSCP --set-dscp-class AF41 2>/dev/null
        iptables -t mangle -A PREROUTING  -i "$IFACE" -p tcp --sport 443 -j DSCP --set-dscp-class AF41 2>/dev/null

        # UDP media (QUIC/HTTP3, Twitch)
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p udp --dport 443 -j DSCP --set-dscp-class AF41 2>/dev/null
        iptables -t mangle -A PREROUTING  -i "$IFACE" -p udp --sport 443 -j DSCP --set-dscp-class AF41 2>/dev/null

        # RTMP streaming
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp --dport 1935 -j DSCP --set-dscp-class AF41 2>/dev/null
        iptables -t mangle -A PREROUTING  -i "$IFACE" -p tcp --sport 1935 -j DSCP --set-dscp-class AF41 2>/dev/null

        # Bulk → thấp hơn
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp -m connbytes \
            --connbytes 5000000: --connbytes-dir both --connbytes-mode bytes \
            -j DSCP --set-dscp-class CS1 2>/dev/null
        ;;

    wfh)
        # Ưu tiên: VoIP/Video call > Web > Bulk
        # EF   (0xb8): Zoom/Meet/Teams audio+video
        # AF31 (0x68): HTTP/HTTPS web browsing
        # CS1  (0x20): bulk
        log "Preset: Work From Home"

        # Zoom UDP (audio/video)
        for ports in "3478:3479" "8801:8802" "8803:8803"; do
            START="${ports%:*}"; END="${ports#*:}"
            iptables -t mangle -A POSTROUTING -o "$IFACE" -p udp --dport "$START:$END" -j DSCP --set-dscp-class EF 2>/dev/null
            iptables -t mangle -A PREROUTING  -i "$IFACE" -p udp --sport "$START:$END" -j DSCP --set-dscp-class EF 2>/dev/null
        done

        # Google Meet / MS Teams UDP
        for ports in "19302:19309" "3478:3481" "50000:50059"; do
            START="${ports%:*}"; END="${ports#*:}"
            iptables -t mangle -A POSTROUTING -o "$IFACE" -p udp --dport "$START:$END" -j DSCP --set-dscp-class EF 2>/dev/null
            iptables -t mangle -A PREROUTING  -i "$IFACE" -p udp --sport "$START:$END" -j DSCP --set-dscp-class EF 2>/dev/null
        done

        # Web browsing HTTPS → AF31
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp --dport 443 -j DSCP --set-dscp-class AF31 2>/dev/null
        iptables -t mangle -A PREROUTING  -i "$IFACE" -p tcp --sport 443 -j DSCP --set-dscp-class AF31 2>/dev/null
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp --dport 80  -j DSCP --set-dscp-class AF31 2>/dev/null
        iptables -t mangle -A PREROUTING  -i "$IFACE" -p tcp --sport 80  -j DSCP --set-dscp-class AF31 2>/dev/null

        # Bulk → CS1
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp -m connbytes \
            --connbytes 2000000: --connbytes-dir both --connbytes-mode bytes \
            -j DSCP --set-dscp-class CS1 2>/dev/null
        ;;

    balanced)
        # Chỉ ECN + bulk throttle, không ưu tiên app cụ thể
        log "Preset: Balanced"
        iptables -t mangle -A POSTROUTING -o "$IFACE" -p tcp -m connbytes \
            --connbytes 10000000: --connbytes-dir both --connbytes-mode bytes \
            -j DSCP --set-dscp-class CS1 2>/dev/null
        ;;

    custom)
        # Dùng sqm_game_ports do user nhập
        log "Preset: Custom (ports: $CUSTOM_PORTS)"
        [ -z "$CUSTOM_PORTS" ] && CUSTOM_PORTS="5000-5060,8001-8002"

        echo "$CUSTOM_PORTS" | tr ',' '\n' | while read port_range; do
            port_range="$(echo "$port_range" | tr -d ' ')"
            [ -z "$port_range" ] && continue
            if echo "$port_range" | grep -q '-'; then
                START="$(echo "$port_range" | cut -d'-' -f1)"
                END="$(echo "$port_range" | cut -d'-' -f2)"
            else
                START="$port_range"; END="$port_range"
            fi
            iptables -t mangle -A POSTROUTING -o "$IFACE" -p udp --dport "$START:$END" -j DSCP --set-dscp-class EF 2>/dev/null
            iptables -t mangle -A PREROUTING  -i "$IFACE" -p udp --sport "$START:$END" -j DSCP --set-dscp-class EF 2>/dev/null
        done
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

    # Class 1:20 → EF/AF41 high priority
    tc class add dev "$IFACE" parent 1:1 classid 1:20 htb rate "$UP_KBIT" ceil "$UP_KBIT" prio 1
    tc qdisc add dev "$IFACE" parent 1:20 fq_codel ecn

    # Class 1:30 → CS1 bulk low priority  
    tc class add dev "$IFACE" parent 1:1 classid 1:30 htb rate "$UP_KBIT" ceil "$UP_KBIT" prio 3
    tc qdisc add dev "$IFACE" parent 1:30 fq_codel ecn

    # Streaming có thêm class AF41 medium-high
    if [ "$PRESET" = "streaming" ] || [ "$PRESET" = "wfh" ]; then
        tc class add dev "$IFACE" parent 1:1 classid 1:25 htb rate "$UP_KBIT" ceil "$UP_KBIT" prio 2
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
