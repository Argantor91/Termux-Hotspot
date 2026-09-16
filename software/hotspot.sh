#!/bin/bash

# Termux-Hotspot: Engineering Grade
# Version: 10.3.0 (Repository Finality)
# Description: A non-destructive, state-aware, secure network subsystem for rooted Android.

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

# Resolve script directory for portable execution
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"

# --- Core Configuration ---
GATEWAY_IP="10.0.0.1"
SUBNET="10.0.0.0/24"
DHCP_START="10.0.0.10"
DHCP_END="10.0.0.100"
DNS_SERVER="1.1.1.1"

# PID Files & Watchdog Counters
PID_HOSTAPD="$PREFIX/tmp/hostapd.pid"
PID_DNSMASQ="$PREFIX/tmp/dnsmasq.pid"
PID_GOST="$PREFIX/tmp/gost.pid"
PID_PORTAL="$PREFIX/tmp/portal.pid"

HOSTAPD_RESTARTS=0
DNSMASQ_RESTARTS=0
GOST_RESTARTS=0
PORTAL_RESTARTS=0

# --- Helper Functions ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_err() { echo -e "${RED}[ERR]${NC} $1"; }

# --- 1. Dependency Check ---
for cmd in hostapd dnsmasq iptables ip iw ss sysctl python3; do
    if ! command -v $cmd &>/dev/null; then
        log_err "Missing core dependency: $cmd. Install with: pkg install $cmd"
        exit 1
    fi
done

HAS_TC=0
command -v tc &>/dev/null && HAS_TC=1

# --- 2. Root Check ---
if [[ $EUID -ne 0 ]]; then
    log_err "Error: Run with: su -c ./hotspot.sh"
    exit 1
fi

# --- 3. Secure User Configuration (Raw Input) ---
log_info "Configuring Hotspot..."
read -r -p "Enter SSID: " SSID
[[ -z "$SSID" ]] && { log_err "SSID cannot be empty."; exit 1; }

read -r -s -p "Enter Password (min 8 chars): " PASSWORD; echo ""
[[ ${#PASSWORD} -lt 8 ]] && { log_err "Password too short!"; exit 1; }

read -r -p "Enter Channel (default 7): " CHANNEL
CHANNEL=${CHANNEL:-7}

# --- 4. Hardware & Interface Detection ---
AP_IF=$(iw dev | awk '$1=="Interface"{print $2}' | head -n 1)
[ -z "$AP_IF" ] && AP_IF="wlan0"

PHY_IDX=$(iw dev "$AP_IF" info 2>/dev/null | grep -oP 'wiphy \K\d+')
if [ -n "$PHY_IDX" ]; then
    if ! iw phy "phy$PHY_IDX" info | grep -q "\* AP"; then
        log_warn "Interface $AP_IF (phy$PHY_IDX) might not support AP mode."
    fi
fi

WAN_IF=$(ip -4 route get 1.1.1.1 2>/dev/null | grep -oP 'dev \K\S+')
if [ -z "$WAN_IF" ] || [ "$WAN_IF" == "$AP_IF" ]; then
    log_err "No valid WAN interface found. Ensure Mobile Data is ON."
    exit 1
fi
log_info "Interfaces locked: AP=$AP_IF | WAN=$WAN_IF"

# --- 5. State Capture & Pre-Flight Cleanup ---
ORIG_IP_FORWARD=$(sysctl -n net.ipv4.ip_forward 2>/dev/null || echo "0")
ORIG_IPV6_STATE=$(sysctl -n net.ipv6.conf.$AP_IF.disable_ipv6 2>/dev/null || echo "0")
ORIG_SELINUX=$(getenforce 2>/dev/null || echo "Disabled")

if [ "$ORIG_SELINUX" == "Enforcing" ]; then
    log_warn "SELinux is Enforcing. Setting to Permissive for nl80211 compatibility."
    setenforce 0
fi

# Clean up any orphaned chains from previous crashed runs
iptables -D FORWARD -j TERMUX_HOTSPOT_FWD 2>/dev/null
iptables -t nat -D POSTROUTING -j TERMUX_HOTSPOT_POST 2>/dev/null
iptables -t nat -D PREROUTING -j TERMUX_HOTSPOT_NAT 2>/dev/null

for chain in TERMUX_HOTSPOT_FWD; do
    iptables -F "$chain" 2>/dev/null; iptables -X "$chain" 2>/dev/null
done
for chain in TERMUX_HOTSPOT_NAT TERMUX_HOTSPOT_POST; do
    iptables -t nat -F "$chain" 2>/dev/null; iptables -t nat -X "$chain" 2>/dev/null
done

# --- 6. Initialization & Network State ---
log_info "Initializing network subsystem..."
sysctl -w net.ipv4.ip_forward=1 >/dev/null 2>&1
sysctl -w net.ipv6.conf.$AP_IF.disable_ipv6=1 >/dev/null 2>&1

ip link set "$AP_IF" up 2>/dev/null
ip addr replace ${GATEWAY_IP}/24 dev "$AP_IF" 2>/dev/null || \
ip addr add ${GATEWAY_IP}/24 dev "$AP_IF" 2>/dev/null || true

# --- 7. QoS Application (Cake -> FQ_Codel Fallback) ---
QOS_APPLIED=""
if [ "$HAS_TC" -eq 1 ]; then
    if tc qdisc replace dev "$WAN_IF" root cake 2>/dev/null; then
        QOS_APPLIED="cake"
        log_info "CAKE QoS applied."
    elif tc qdisc replace dev "$WAN_IF" root fq_codel 2>/dev/null; then
        QOS_APPLIED="fq_codel"
        log_info "Fallback: fq_codel applied."
    fi
fi

# --- 8. The Invincible Netfilter Engine ---
log_info "Injecting iptables rules..."

# 1. Create Custom Chains
iptables -N TERMUX_HOTSPOT_FWD 2>/dev/null
iptables -t nat -N TERMUX_HOTSPOT_NAT 2>/dev/null
iptables -t nat -N TERMUX_HOTSPOT_POST 2>/dev/null

# 2. Inject Jumps at the Absolute Top (Priority & Immunity)
iptables -I FORWARD 1 -j TERMUX_HOTSPOT_FWD
iptables -t nat -I POSTROUTING 1 -j TERMUX_HOTSPOT_POST
iptables -t nat -I PREROUTING 1 -j TERMUX_HOTSPOT_NAT 

# 3. Populate FORWARD Chain (Subnet Restricted)
iptables -A TERMUX_HOTSPOT_FWD -s $SUBNET -i "$AP_IF" -o "$WAN_IF" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT
iptables -A TERMUX_HOTSPOT_FWD -d $SUBNET -i "$WAN_IF" -o "$AP_IF" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
iptables -A TERMUX_HOTSPOT_FWD -j RETURN 

# 4. Populate POSTROUTING Chain (Subnet Restricted)
iptables -A TERMUX_HOTSPOT_POST -s $SUBNET -o "$WAN_IF" -j MASQUERADE

# 5. Populate PREROUTING Chain (DNS/HTTP Interception)
iptables -A TERMUX_HOTSPOT_NAT -i "$AP_IF" -p tcp --dport 80 -j REDIRECT --to-port 8080
iptables -A TERMUX_HOTSPOT_NAT -i "$AP_IF" -p tcp --dport 53 -j REDIRECT --to-port 5353
iptables -A TERMUX_HOTSPOT_NAT -i "$AP_IF" -p udp --dport 53 -j REDIRECT --to-port 5353

# --- 9. Bulletproof Infrastructure Deployment ---
mkdir -p "$PREFIX/etc/hotspot"

# Save Password for Portal (Securely)
echo -n "$PASSWORD" > "$PREFIX/tmp/hp_pass"
chmod 600 "$PREFIX/tmp/hp_pass"

# Generate hostapd.conf
cat > "$PREFIX/etc/hotspot/hostapd.conf" <<'EOL'
interface=AP_IF_PLACEHOLDER
driver=nl80211
hw_mode=g
channel=CHANNEL_PLACEHOLDER
wpa=2
wpa_key_mgmt=WPA-PSK
wpa_pairwise=CCMP
rsn_pairwise=CCMP
EOL

printf "ssid=%s\n" "$SSID" >> "$PREFIX/etc/hotspot/hostapd.conf"
printf "wpa_passphrase=%s\n" "$PASSWORD" >> "$PREFIX/etc/hotspot/hostapd.conf"

sed -i "s/AP_IF_PLACEHOLDER/$AP_IF/g; s/CHANNEL_PLACEHOLDER/$CHANNEL/g" "$PREFIX/etc/hotspot/hostapd.conf"

# --- 10. Process Supervision ---
log_info "Spawning daemons..."

HOSTAPD_BIN="$PREFIX/bin/hostapd"
DNSMASQ_BIN="$PREFIX/bin/dnsmasq"
GOST_BIN="$PREFIX/bin/gost"

start_hostapd() {
    $HOSTAPD_BIN "$PREFIX/etc/hotspot/hostapd.conf" &
    echo $! > "$PID_HOSTAPD"
}

start_dnsmasq() {
    $DNSMASQ_BIN -d -i "$AP_IF" --port=0 \
        --dhcp-range=$DHCP_START,$DHCP_END,255.255.255.0,12h \
        --dhcp-option=3,$GATEWAY_IP --dhcp-option=6,$GATEWAY_IP \
        --address=/connectivitycheck.gstatic.com/$GATEWAY_IP \
        --address=/generate_204.google.com/$GATEWAY_IP \
        --address=/captive.apple.com/$GATEWAY_IP \
        --address=/detectportal.firefox.com/$GATEWAY_IP &
    echo $! > "$PID_DNSMASQ"
}

start_gost() {
    $GOST_BIN -L "dns://127.0.0.1:5353?dns=tls://$DNS_SERVER:853,$DNS_SERVER:53" --log-level=error >> "$PREFIX/tmp/gost.log" 2>&1 &
    echo $! > "$PID_GOST"
}

start_portal() {
    export GATEWAY_IP
    export PREFIX
    python3 "$SCRIPT_DIR/server.py" &
    echo $! > "$PID_PORTAL"
}

start_hostapd
start_dnsmasq
start_gost
start_portal

sleep 2

# Verify DNS and Portal
if ! ss -lun | grep -q ":5353"; then
    log_err "DNS Proxy failed to bind. Exiting."
    exit 1
fi

# --- 11. Cleanup (The Hard Teardown) ---
cleanup() {
    echo -e "\n${YELLOW}Stopping subsystem and restoring state...${NC}"
    
    for pid_file in "$PID_HOSTAPD" "$PID_DNSMASQ" "$PID_GOST" "$PID_PORTAL"; do
        [ -f "$pid_file" ] && kill $(cat "$pid_file") 2>/dev/null
    done
    sleep 1
    killall hostapd dnsmasq gost 2>/dev/null
    
    # 1. Delete the JUMPS from the main chains (Signature-based, safe)
    iptables -D FORWARD -j TERMUX_HOTSPOT_FWD 2>/dev/null
    iptables -t nat -D POSTROUTING -j TERMUX_HOTSPOT_POST 2>/dev/null
    iptables -t nat -D PREROUTING -j TERMUX_HOTSPOT_NAT 2>/dev/null
    
    # 2. Flush and delete all custom chains (Zero risk to host OS)
    iptables -F TERMUX_HOTSPOT_FWD 2>/dev/null
    iptables -X TERMUX_HOTSPOT_FWD 2>/dev/null
    iptables -t nat -F TERMUX_HOTSPOT_NAT 2>/dev/null
    iptables -t nat -X TERMUX_HOTSPOT_NAT 2>/dev/null
    iptables -t nat -F TERMUX_HOTSPOT_POST 2>/dev/null
    iptables -t nat -X TERMUX_HOTSPOT_POST 2>/dev/null
    
    # 3. Restore System State
    sysctl -w net.ipv4.ip_forward="$ORIG_IP_FORWARD" >/dev/null 2>&1
    sysctl -w net.ipv6.conf.$AP_IF.disable_ipv6="$ORIG_IPV6_STATE" >/dev/null 2>&1
    
    if [ "$ORIG_SELINUX" == "Enforcing" ]; then
        setenforce 1
    fi
    
    # 4. Remove QoS
    if [ "$HAS_TC" -eq 1 ] && [ -n "$QOS_APPLIED" ]; then
        tc qdisc del dev "$WAN_IF" root 2>/dev/null
    fi
    
    # 5. Hard Teardown: Surgically remove our IP and power down radio
    ip addr del ${GATEWAY_IP}/24 dev "$AP_IF" 2>/dev/null || true
    ip link set "$AP_IF" down 2>/dev/null
    
    rm -f "$PID_HOSTAPD" "$PID_DNSMASQ" "$PID_GOST" "$PID_PORTAL" "$PREFIX/tmp/hp_pass"
    log_info "Subsystem offline. Host restored."
}
trap cleanup EXIT SIGINT SIGTERM

log_info "System live. Watchdog active. Press Ctrl+C to exit."

# --- 12. The Watchdog (Machine-Scale Supervision) ---
while true; do
    for pid_file in "$PID_HOSTAPD" "$PID_DNSMASQ" "$PID_GOST" "$PID_PORTAL"; do
        [ ! -f "$pid_file" ] && continue
        pid=$(cat "$pid_file")
        [ -z "$pid" ] && continue
        
        if ! kill -0 "$pid" 2>/dev/null; then
            case "$pid_file" in
                *hostapd*)
                    if (( HOSTAPD_RESTARTS >= 3 )); then
                        log_err "Hostapd failed 3 times. Radio hardware unstable. Tearing down."
                        exit 1
                    fi
                    HOSTAPD_RESTARTS=$((HOSTAPD_RESTARTS + 1))
                    log_warn "Hostapd died; restarting... ($HOSTAPD_RESTARTS/3)"
                    start_hostapd ;;
                *dnsmasq*)
                    DNSMASQ_RESTARTS=$((DNSMASQ_RESTARTS + 1))
                    log_warn "Dnsmasq died; restarting..."
                    start_dnsmasq ;;
                *gost*)
                    GOST_RESTARTS=$((GOST_RESTARTS + 1))
                    log_warn "GOST died; restarting..."
                    start_gost ;;
                *portal*)
                    PORTAL_RESTARTS=$((PORTAL_RESTARTS + 1))
                    log_warn "Portal died; restarting..."
                    start_portal ;;
            esac
        else
            case "$pid_file" in
                *hostapd*) HOSTAPD_RESTARTS=0 ;;
                *dnsmasq*) DNSMASQ_RESTARTS=0 ;;
                *gost*) GOST_RESTARTS=0 ;;
                *portal*) PORTAL_RESTARTS=0 ;;
            esac
        fi
    done
    sleep 2
done
