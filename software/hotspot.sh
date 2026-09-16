#!/bin/bash

# Termux-Hotspot: Engineering Grade
# Version: 9.3.0 (The "Absolute Certainty" Edition)
# Description: A non-destructive, state-aware network subsystem for rooted Android.

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

# --- Environment Reconstruction ---
if [ -z "$PREFIX" ]; then
    export PREFIX='/data/data/com.termux/files/usr'
fi
export PATH="$PREFIX/bin:$PREFIX/sbin:$PATH"

# --- Core Configuration ---
GATEWAY_IP="10.0.0.1"
DHCP_START="10.0.0.10"
DHCP_END="10.0.0.100"
DNS_SERVER="1.1.1.1"

# PID Files
PID_HOSTAPD="$PREFIX/tmp/hostapd.pid"
PID_DNSMASQ="$PREFIX/tmp/dnsmasq.pid"
PID_GOST="$PREFIX/tmp/gost.pid"

# --- Helper Functions ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERR]${NC} $1"; }

# --- 1. Dependency Check ---
for cmd in hostapd dnsmasq iptables ip iw ss sysctl tc; do
    if ! command -v $cmd &>/dev/null; then
        log_err "Missing: $cmd. Install with: pkg install $cmd"
        exit 1
    fi
done

# --- 2. Root Check ---
if [[ $EUID -ne 0 ]]; then
    log_err "Error: Run with: su -c ./hotspot.sh"
    exit 1
fi

# --- 3. User Configuration ---
read -p "Enter SSID: " SSID
read -sp "Enter Password (min 8 chars): " PASSWORD; echo ""
[ ${#PASSWORD} -lt 8 ] && { log_err "Password too short!"; exit 1; }
read -p "Enter Channel (default 7): " CHANNEL
CHANNEL=${CHANNEL:-7}

# --- 4. Hardware & Interface Detection ---
# Robust AP detection via iw
AP_IF=$(iw dev | awk '$1=="Interface"{print $2}' | head -n 1)
[ -z "$AP_IF" ] && AP_IF="wlan0"

# Robust WAN detection via active routing table
WAN_IF=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+')
if [ -z "$WAN_IF" ] || [ "$WAN_IF" == "$AP_IF" ]; then
    log_err "No valid WAN interface found. Ensure Mobile Data is ON."
    exit 1
fi
log_info "Interfaces locked: AP=$AP_IF | WAN=$WAN_IF"

# --- 5. State Capture ---
ORIG_IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
ORIG_IPV6_STATE=$(sysctl -n net.ipv6.conf.$AP_IF.disable_ipv6 2>/dev/null || echo "0")

# Clean up any orphaned chains from previous crashed runs
iptables -D FORWARD -j TERMUX_HOTSPOT 2>/dev/null
iptables -F TERMUX_HOTSPOT 2>/dev/null
iptables -X TERMUX_HOTSPOT 2>/dev/null
iptables -t nat -D PREROUTING -j TERMUX_HOTSPOT_NAT 2>/dev/null
iptables -t nat -F TERMUX_HOTSPOT_NAT 2>/dev/null
iptables -t nat -X TERMUX_HOTSPOT_NAT 2>/dev/null

# --- 6. Initialization & Network State ---
log_info "Initializing network subsystem..."

# Enable IP Forwarding (Fixed: explicitly set to 1, not ORIG)
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1

# Disable IPv6 on AP to force consistent IPv4 NAT behavior
sysctl -w net.ipv6.conf.$AP_IF.disable_ipv6=1 >/dev/null 2>&1

# Idempotent IP assignment
ip addr replace ${GATEWAY_IP}/24 dev "$AP_IF" 2>/dev/null || \
ip addr add ${GATEWAY_IP}/24 dev "$AP_IF" 2>/dev/null || true

# --- 7. QoS Application (Cake -> FQ_Codel Fallback) ---
QOS_APPLIED=""
if tc qdisc replace dev "$WAN_IF" root cake 2>/dev/null; then
    QOS_APPLIED="cake"
    log_info "CAKE QoS applied."
elif tc qdisc replace dev "$WAN_IF" root fq_codel 2>/dev/null; then
    QOS_APPLIED="fq_codel"
    log_info "Fallback: fq_codel applied."
fi

# --- 8. Iptables Engine (Injection & Dedicated Chains) ---
log_info "Injecting iptables rules..."

# Create custom chains in their correct tables
iptables -N TERMUX_HOTSPOT
iptables -t nat -N TERMUX_HOTSPOT_NAT

# Inject explicit allows at the top of the FORWARD chain
iptables -I FORWARD 1 -i "$AP_IF" -o "$WAN_IF" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -I FORWARD 2 -i "$WAN_IF" -o "$AP_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A FORWARD -j TERMUX_HOTSPOT
iptables -A TERMUX_HOTSPOT -j ACCEPT

# NAT rules (Fixed: Added UDP, fixed chain jumping)
iptables -t nat -A POSTROUTING -o "$WAN_IF" -j MASQUERADE
iptables -t nat -A PREROUTING -i "$AP_IF" -p tcp --dport 53 -j TERMUX_HOTSPOT_NAT
iptables -t nat -A PREROUTING -i "$AP_IF" -p udp --dport 53 -j TERMUX_HOTSPOT_NAT
iptables -t nat -A TERMUX_HOTSPOT_NAT -j REDIRECT --to-port 5353

# --- 9. Infrastructure Deployment ---
mkdir -p "$PREFIX/etc/hostapd"
cat > "$PREFIX/etc/hostapd/hostapd.conf" <<EOL
interface=$AP_IF
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOL

# --- 10. Process Supervision ---
log_info "Spawning daemons..."

HOSTAPD_BIN="$PREFIX/bin/hostapd"
DNSMASQ_BIN="$PREFIX/bin/dnsmasq"
GOST_BIN="$PREFIX/bin/gost"

start_hostapd() {
    $HOSTAPD_BIN "$PREFIX/etc/hostapd/hostapd.conf" &
    echo $! > "$PID_HOSTAPD"
}

start_dnsmasq() {
    # Fixed: Port 0 stops dnsmasq from binding to 53, avoiding collision with GOST
    $DNSMASQ_BIN -d -i "$AP_IF" --port=0 --dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,12h --dhcp-option=3,$GATEWAY_IP --dhcp-option=6,$GATEWAY_IP &
    echo $! > "$PID_DNSMASQ"
}

start_gost() {
    # GOST listens on 5353 (which iptables redirects to), and forwards to upstream
    $GOST_BIN -L "dns://127.0.0.1:5353?dns=tls://$DNS_SERVER:853" --log-level=error &
    echo $! > "$PID_GOST"
}

start_hostapd
start_dnsmasq
start_gost

sleep 2
if ! ss -lun | grep -q ":5353"; then
    log_err "DNS Proxy failed to bind. Exiting."
    exit 1
fi

# --- 11. Cleanup (The Destructive Restoration) ---
cleanup() {
    echo -e "\n${YELLOW}Stopping subsystem and restoring state...${NC}"
    
    # Kill tracked PIDs
    for pid_file in "$PID_HOSTAPD" "$PID_DNSMASQ" "$PID_GOST"; do
        [ -f "$pid_file" ] && kill $(cat "$pid_file") 2>/dev/null
    done
    sleep 1
    killall hostapd dnsmasq gost 2>/dev/null
    
    # Delete injected rules (Fixed: Removed invalid position numbers)
    iptables -D FORWARD -i "$AP_IF" -o "$WAN_IF" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    iptables -D FORWARD -i "$WAN_IF" -o "$AP_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null
    iptables -D FORWARD -j TERMUX_HOTSPOT 2>/dev/null
    
    iptables -t nat -D POSTROUTING -o "$WAN_IF" -j MASQUERADE 2>/dev/null
    iptables -t nat -D PREROUTING -i "$AP_IF" -p tcp --dport 53 -j TERMUX_HOTSPOT_NAT 2>/dev/null
    iptables -t nat -D PREROUTING -i "$AP_IF" -p udp --dport 53 -j TERMUX_HOTSPOT_NAT 2>/dev/null
    
    # Flush and delete custom chains
    iptables -F TERMUX_HOTSPOT 2>/dev/null
    iptables -X TERMUX_HOTSPOT 2>/dev/null
    iptables -t nat -F TERMUX_HOTSPOT_NAT 2>/dev/null
    iptables -t nat -X TERMUX_HOTSPOT_NAT 2>/dev/null
    
    # Restore states
    sysctl -w net.ipv4.ip_forward="$ORIG_IP_FORWARD" >/dev/null 2>&1
    sysctl -w net.ipv6.conf.$AP_IF.disable_ipv6="$ORIG_IPV6_STATE" >/dev/null 2>&1
    
    # Remove QoS
    if [ -n "$QOS_APPLIED" ]; then
        tc qdisc del dev "$WAN_IF" root 2>/dev/null
    fi
    
    ip addr del ${GATEWAY_IP}/24 dev "$AP_IF" 2>/dev/null || true
    rm -f "$PID_HOSTAPD" "$PID_DNSMASQ" "$PID_GOST"
    log_info "Subsystem offline. Host restored."
}
trap cleanup EXIT SIGINT SIGTERM

log_info "System live. Watchdog active. Press Ctrl+C to exit."

# --- 12. The Watchdog (Machine-Scale Supervision) ---
while true; do
    for pid_file in "$PID_HOSTAPD" "$PID_DNSMASQ" "$PID_GOST"; do
        [ ! -f "$pid_file" ] && continue
        pid=$(cat "$pid_file")
        [ -z "$pid" ] && continue
        
        if ! kill -0 "$pid" 2>/dev/null; then
            log_warn "$(basename "$pid_file" .pid) died; restarting..."
            case "$pid_file" in
                *hostapd*) start_hostapd ;;
                *dnsmasq*) start_dnsmasq ;;
                *gost*)    start_gost ;;
            esac
        fi
    done
    sleep 2
done
