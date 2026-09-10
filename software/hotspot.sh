#!/bin/bash

# Termux-Hotspot: Resilient Service-Manager Edition
# Features: Targeted Service Restarts, Multi-threaded Python, Secure Password, Seamless Portal

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

# --- Environment Setup ---
# Ensure we are using Termux-specific paths even if run via tsu
if [ -z "$PREFIX" ]; then
    export PREFIX='/data/data/com.termux/files/usr'
else
    export PREFIX="$PREFIX"
fi
export PATH="$PREFIX/bin:$PATH"

# --- Core Configuration ---
GATEWAY_IP="192.168.1.1"
TEMP_PASS_FILE="$PREFIX/tmp/hp_pass"

# --- Helper Functions ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 1. Dependency Check ---
check_deps() {
    local missing=0
    for cmd in hostapd dnsmasq iptables curl python3 tsu; do
        if ! command -v $cmd &>/dev/null; then
            log_error "Missing: $cmd. Install with: pkg install $cmd"
            missing=1
        fi
    done
    [ $missing -eq 1 ] && exit 1
}
check_deps

# --- 2. Root & Environment Check ---
if [[ $EUID -ne 0 ]]; then
    log_error "Run with: tsu ./hotspot.sh"
    exit 1
fi

# --- 3. User Configuration ---
log_info "Configuring Hotspot..."
read -p "Enter SSID: " SSID
read -sp "Enter Password (min 8 chars): " PASSWORD; echo ""
if [ ${#PASSWORD} -lt 8 ]; then
    log_error "Password too short!"; exit 1
fi

# Securely store password for Python access (chmod 600)
echo "$PASSWORD" > "$TEMP_PASS_FILE"
chmod 600 "$TEMP_PASS_FILE"

read -p "Enter Channel (default 7): " CHANNEL
CHANNEL=${CHANNEL:-7}

# --- 4. Dynamic Interface Detection ---
# Finds the Wi-Fi/WLAN interface that is currently UP
AP_IF=$(ip link show | grep -E 'wlan|wifi' | awk -F': ' '{print $2}' | head -n 1)
[ -z "$AP_IF" ] && { AP_IF="wlan0"; log_warn "Defaulting to wlan0"; }

# Detect WAN Interface (the source of internet)
WAN_IF=$(ip route | grep default | awk '{print $5}' | head -n 1)
if [ -z "$WAN_IF" ] || [ "$WAN_IF" == "$AP_IF" ]; then
    log_error "No valid WAN interface found (Ensure Cellular/USB tethering is ON)."; exit 1
fi
log_info "WAN: $WAN_IF | AP: $AP_IF"

# --- 5. QoS (CAKE/Iptables) ---
log_info "Configuring QoS..."
if command -v tc &>/dev/null && tc qdisc replace dev $WAN_IF root cake 2>/dev/null; then
    log_info "CAKE QDisc enabled (Bufferbloat mitigation)."
else
    log_warn "CAKE unavailable. Using iptables rate limit fallback."
    iptables -A FORWARD -i $AP_IF -o $WAN_IF -m limit --limit 5/second --limit-burst 20 -j ACCEPT
fi

# --- 6. Service Definition (The Fail-over Engine) ---

# These functions allow the monitor loop to restart ONLY the failed service
start_hostapd() {
    log_info "Starting hostapd..."
    hostapd "$PREFIX/etc/hostapd/hostapd.conf" -B
    return $?
}

start_dnsmasq() {
    log_info "Starting dnsmasq..."
    dnsmasq -C "$PREFIX/etc/dnsmasq.conf" -B
    return $?
}

start_gost() {
    log_info "Starting GOST DNS Proxy..."
    gost -L dns://127.0.0.1:5353?adblock=$ADBLOCK_LIST&forward=9.9.9.9:53,1.1.1.1:53 --log-level=error &
    return $?
}

start_python() {
    log_info "Starting Captive Portal..."
    export GATEWAY_IP
    python3 server.py &
    return $?
}

# --- 7. Initial Setup & Pre-flight ---
log_info "Preparing Network Infrastructure..."

# Setup Config Files
mkdir -p "$PREFIX/etc/hostapd" "$PREFIX/etc/dnsmasq"

cat > "$PREFIX/etc/hostapd/hostapd.conf" <<EOL
interface=$AP_IF
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
beacon_int=100
dtim_period=2
EOL

cat > "$PREFIX/etc/dnsmasq.conf" <<EOL
interface=$AP_IF
dhcp-range=${GATEWAY_IP}+2,${GATEWAY_IP}+100,255.255.255.0,12h
dhcp-option=3,${GATEWAY_IP}
dhcp-option=6,${GATEWAY_IP}
server=127.0.0.1#5353
# Seamlessness: Redirect common detection domains to the gateway
address=/google.com/${GATEWAY_IP}
address=/gstatic.com/${GATEWAY_IP}
address=/apple.com/${GATEWAY_IP}
address=/w3.org/${GATEWAY_IP}
EOL

# Setup Routing & NAT
iptables -t nat -F POSTROUTING 2>/dev/null
iptables -F FORWARD 2>/dev/null
ip addr add ${GATEWAY_IP}/24 dev $AP_IF 2>/dev/null
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE
iptables -A FORWARD -i $AP_IF -o $WAN_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $WAN_IF -o $AP_IF -j ACCEPT
iptables -t nat -A PREROUTING -i $AP_IF -p tcp --dport 80 -j REDIRECT --to-port 8080

# GOST Adblocking Setup
ADBLOCK_LIST="$PREFIX/adblock.list"
log_info "Syncing Adblock list..."
curl -sL -o "$ADBLOCK_LIST" "https://raw.githubusercontent.com/hagezi/dns-blocklists/master/light.txt" || \
curl -sL -o "$ADBLOCK_LIST" "https://raw.githubusercontent.com/hagezi/dns-blocklists/master/facebook.txt"

if ! command -v gost &>/dev/null; then
    log_info "Installing GOST binary..."
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && G_URL="https://github.com/ginuerzh/gost/releases/latest/download/gost-linux-arm64"
    [[ "$ARCH" == "armv7l" || "$ARCH" == "arm" ]] && G_URL="https://github.com/ginuerzh/gost/releases/latest/download/gost-linux-armv7"
    [[ -z "$G_URL" ]] && G_URL="https://github.com/ginuerzh/gost/releases/latest/download/gost-linux-amd64"
    curl -sL -o "$PREFIX/bin/gost" "$G_URL" && chmod +x "$PREFIX/bin/gost"
fi

# --- 8. Launch and Monitor ---
# Initial Start
start_hostapd || { log_error "hostapd failed!"; exit 1; }
start_dnsmasq || { log_error "dnsmasq failed!"; exit 1; }
start_gost || { log_error "gost failed!"; exit 1; }
start_python || { log_error "python failed!"; exit 1; }

# Cleanup on exit
cleanup() {
    echo -e "\n${YELLOW}Stopping all services...${NC}"
    killall -9 hostapd dnsmasq python3 gost 2>/dev/null
    iptables -t nat -F POSTROUTING 2>/dev/null
    iptables -F FORWARD 2>/dev/null
    rm -f "$TEMP_PASS_FILE"
    log_info "Done."
}
trap cleanup EXIT SIGINT SIGTERM

log_info "All services running. Monitoring for failures..."

# The "Smart Fail-over" Loop
# We use pgrep to find the real PIDs dynamically
while true; do
    # 1. Check hostapd
    if ! pgrep -f "hostapd $PREFIX/etc/hostapd/hostapd.conf" >/dev/null; then
        log_warn "hostapd died! Restarting..."
        start_hostapd
    fi
    # 2. Check dnsmasq
    if ! pgrep -f "dnsmasq -C $PREFIX/etc/dnsmasq.conf" >/dev/null; then
        log_warn "dnsmasq died! Restarting..."
        start_dnsmasq
    fi
    # 3. Check gost
    if ! pgrep -f "gost -L dns://127.0.0.1:5353" >/dev/null; then
        log_warn "gost died! Restarting..."
        start_gost
    fi
    # 4. Check python
    if ! pgrep -f "python3 server.py" >/dev/null; then
        log_warn "Captive Portal died! Restarting..."
        start_python
    fi
    sleep 3
done
