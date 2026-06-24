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
#   sqm_game     : 0/1 Game Priority (ECN + DSCP + UDP port filter)
#   sqm_game_ports: UDP port ranges, comma-separated (e.g. 5000-5060,8001-8002)
#

SQM_LOCK="/var/run/sqm.lock"

get_nvram() {
    nvram get "$1"
}

log() {
    logger -t "SQM" "$1"
}

stop_sqm() {
    log "Stopping SQM..."

    IFACE="$(get_nvram sqm_iface)"
    [ -z "$IFACE" ] && IFACE="eth3"

    # Remove egress qdisc
    tc qdisc del dev "$IFACE" root 2>/dev/null

    # Remove ingress + IFB
    tc qdisc del dev "$IFACE" ingress 2>/dev/null
    tc qdisc del dev ifb0 root 2>/dev/null
    ip link set ifb0 down 2>/dev/null

    # Remove iptables DSCP marks nếu có
    iptables -t mangle -F POSTROUTING 2>/dev/null

    rm -f "$SQM_LOCK"
    log "SQM stopped"
}

add_game_filters() {
    local IFACE="$1"
    local GAME_PORTS="$2"
    local PRIO=10

    [ -z "$GAME_PORTS" ] && GAME_PORTS="5000-5060,8001-8002"

    log "Adding game UDP filters: $GAME_PORTS"

    # Parse từng port range
    echo "$GAME_PORTS" | tr ',' '\n' | while read port_range; do
        port_range="$(echo "$port_range" | tr -d ' ')"
        [ -z "$port_range" ] && continue

        if echo "$port_range" | grep -q '-'; then
            # Range: e.g. 5000-5060
            START="$(echo "$port_range" | cut -d'-' -f1)"
            END="$(echo "$port_range" | cut -d'-' -f2)"
            # Tính mask cho range (dùng iptables cho đơn giản và chính xác hơn)
            iptables -t mangle -A POSTROUTING -o "$IFACE" \
                -p udp --dport "$START:$END" \
                -j DSCP --set-dscp-class EF 2>/dev/null
            iptables -t mangle -A PREROUTING -i "$IFACE" \
                -p udp --sport "$START:$END" \
                -j DSCP --set-dscp-class EF 2>/dev/null
        else
            # Single port
            iptables -t mangle -A POSTROUTING -o "$IFACE" \
                -p udp --dport "$port_range" \
                -j DSCP --set-dscp-class EF 2>/dev/null
            iptables -t mangle -A PREROUTING -i "$IFACE" \
                -p udp --sport "$port_range" \
                -j DSCP --set-dscp-class EF 2>/dev/null
        fi

        PRIO=$((PRIO + 1))
    done
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
    GAME="$(get_nvram sqm_game)"
    GAME_PORTS="$(get_nvram sqm_game_ports)"

    # Validate
    [ -z "$IFACE" ]    && { log "ERROR: sqm_iface not set"; return 1; }
    [ -z "$DOWN" ]     && { log "ERROR: sqm_down not set"; return 1; }
    [ -z "$UP" ]       && { log "ERROR: sqm_up not set"; return 1; }
    [ -z "$QDISC" ]    && QDISC="fq_codel"
    [ -z "$OVERHEAD" ] && OVERHEAD="0"

    # Game mode bật ECN tự động
    ECN_OPT=""
    [ "$GAME" = "1" ] && ECN_OPT="ecn"

    DOWN_KBIT="${DOWN}kbit"
    UP_KBIT="${UP}kbit"

    log "Starting SQM on $IFACE: down=${DOWN_KBIT} up=${UP_KBIT} qdisc=${QDISC} overhead=${OVERHEAD} game=${GAME}"

    # Load required modules
    modprobe sch_htb      2>/dev/null
    modprobe sch_fq_codel 2>/dev/null
    modprobe ifb          2>/dev/null
    modprobe act_mirred   2>/dev/null
    modprobe xt_DSCP      2>/dev/null
    modprobe xt_dscp      2>/dev/null

    # -------------------------
    # EGRESS (upload shaping)
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

    # Game Priority classes (DSCP EF → 1:20, CS1 bulk → 1:30)
    if [ "$GAME" = "1" ]; then
        # High priority: game/VoIP (EF)
        tc class add dev "$IFACE" parent 1:1 classid 1:20 htb rate "$UP_KBIT" ceil "$UP_KBIT" prio 1
        tc qdisc add dev "$IFACE" parent 1:20 fq_codel ecn
        tc filter add dev "$IFACE" parent 1: protocol ip prio 1 u32 \
            match ip dsfield 0xb8 0xfc flowid 1:20

        # Low priority: bulk (CS1)
        tc class add dev "$IFACE" parent 1:1 classid 1:30 htb rate "$UP_KBIT" ceil "$UP_KBIT" prio 3
        tc qdisc add dev "$IFACE" parent 1:30 fq_codel ecn
        tc filter add dev "$IFACE" parent 1: protocol ip prio 2 u32 \
            match ip dsfield 0x20 0xfc flowid 1:30

        # Thêm iptables DSCP mark cho UDP game ports
        add_game_filters "$IFACE" "$GAME_PORTS"

        log "Game Priority enabled: ECN + DSCP + UDP filter (ports: ${GAME_PORTS:-5000-5060,8001-8002})"
    fi

    # -------------------------
    # INGRESS (download shaping via IFB)
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
    log "SQM started successfully"
}

status_sqm() {
    IFACE="$(get_nvram sqm_iface)"
    echo "=== Egress (upload) ==="
    tc qdisc show dev "$IFACE" 2>/dev/null
    tc class show dev "$IFACE" 2>/dev/null
    echo ""
    echo "=== Ingress via IFB (download) ==="
    tc qdisc show dev ifb0 2>/dev/null
    echo ""
    echo "=== Game DSCP filters ==="
    iptables -t mangle -L POSTROUTING -n 2>/dev/null | grep DSCP
}

case "$1" in
    start)
        [ "$(get_nvram sqm_enable)" = "1" ] && start_sqm
        ;;
    stop)
        stop_sqm
        ;;
    restart)
        stop_sqm
        sleep 1
        [ "$(get_nvram sqm_enable)" = "1" ] && start_sqm
        ;;
    status)
        status_sqm
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status}"
        ;;
esac
