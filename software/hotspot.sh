#!/bin/bash

# Termux-Hotspot Production Build (Resilient Edition)
# Features: Service Monitoring, Multi-threaded Python, Secure Password, Seamless Portal

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' 

# --- Environment Setup ---
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
            log_error "Missing: $cmd. Run: pkg install $cmd"
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
read -sp "Enter Password (min 8 chars): " PASSWORD
echo ""
if [ ${#PASSWORD} -lt 8 ]; then
    log_error "Password too short!"; exit 1
fi

# Securely store password for Python access
echo "$PASSWORD" > "$TEMP_PASS_FILE"
chmod 600 "$TEMP_PASS_FILE"

read -p "Enter Channel (default 7): " CHANNEL
CHANNEL=${CHANNEL:-7}

# --- 4. Dynamic Interface Detection ---
AP_IF=$(ip link show | grep -E 'wlan|wifi' | awk -F': ' '{print $2}' | head -n 1)
[ -z "$AP_IF" ] && { AP_IF="wlan0"; log_warn "Defaulting to wlan0"; }

WAN_IF=$(ip route | grep default | awk '{print $5}' | head -n 1)
if [ -z "$WAN_IF" ] || [ "$WAN_IF" == "$AP_IF" ]; then
    log_error "No valid WAN interface found (Need Cellular/USB tethering)."; exit 1
fi
log_info "WAN: $WAN_IF | AP: $AP_IF"

# --- 5. QoS (CAKE/Iptables) ---
log_info "Configuring QoS..."
if command -v tc &>/dev/null && tc qdisc replace dev $WAN_IF root cake 2>/dev/null; then
    log_info "CAKE QDisc enabled."
else
    log_warn "CAKE unavailable. Using iptables fallback."
    iptables -A FORWARD -i $AP_IF -o $WAN_IF -m limit --limit 5/second --limit-burst 20 -j ACCEPT
fi

# --- 6. Cleanup Routine ---
cleanup() {
    echo -e "\n${YELLOW}Stopping services...${NC}"
    killall -9 hostapd dnsmasq python3 gost 2>/dev/null
    iptables -t nat -F POSTROUTING 2>/dev/null
    iptables -F FORWARD 2>/dev/null
    rm -f "$TEMP_PASS_FILE"
    log_info "Done."
}
trap cleanup EXIT SIGINT SIGTERM

# --- 7. Network & IP Forwarding ---
log_info "Setting up Network Routing..."
iptables -t nat -F POSTROUTING 2>/dev/null
iptables -F FORWARD 2>/dev/null

ip addr add ${GATEWAY_IP}/24 dev $AP_IF 2>/dev/null
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE
iptables -A FORWARD -i $AP_IF -o $WAN_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $WAN_IF -o $AP_IF -j ACCEPT
iptables -t nat -A PREROUTING -i $AP_IF -p tcp --dport 80 -j REDIRECT --to-port 8080

# --- 8. DNS & Adblocking (Reliable GOST) ---
ADBLOCK_LIST="$PREFIX/adblock.list"
log_info "Syncing Adblock list..."
curl -sL -o "$ADBLOCK_LIST" "https://raw.githubusercontent.com/hagezi/dns-blocklists/master/light.txt" || \
curl -sL -o "$ADBLOCK_LIST" "https://raw.githubusercontent.com/hagezi/dns-blocklists/master/facebook.txt"

if ! command -v gost &>/dev/null; then
    log_info "Installing GOST..."
    ARCH=$(uname -m)
    [[ "$ARCH" == "aarch64" || "$ARCH" == "arm64" ]] && G_URL="https://github.com/ginuerzh/gost/releases/latest/download/gost-linux-arm64"
    [[ "$ARCH" == "armv7l" || "$ARCH" == "arm" ]] && G_URL="https://github.com/ginuerzh/gost/releases/latest/download/gost-linux-armv7"
    [[ -z "$G_URL" ]] && G_URL="https://github.com/ginuerzh/gost/releases/latest/download/gost-linux-amd64"
    
    curl -sL -o "$PREFIX/bin/gost" "$G_URL" || { log_error "Gost download failed!"; exit 1; }
    chmod +x "$PREFIX/bin/gost"
fi

gost -L dns://127.0.0.1:5353?adblock=$ADBLOCK_LIST&forward=9.9.9.9:53,1.1.1.1:53 --log-level=error &
GOST_PID=$!

# --- 9. hostapd & dnsmasq Configuration ---
mkdir -p "$PREFIX/etc/hostapd" "$PREFIX/etc/dnsmasq"

cat > "$PREFIX/etc/hostapd/hostapd.conf" <<EOL
interface=$AP_IF
driver=nl80211
ssid=$SSID
hw_mode=g
channel=$CHANNEL
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=$PASSWORD
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
beacon_int=100
dtim_period=2
EOL

# Seamlessness: Force common detection domains to the gateway
cat > "$PREFIX/etc/dnsmasq.conf" <<EOL
interface=$AP_IF
dhcp-range=${GATEWAY_IP}+2,${GATEWAY_IP}+100,255.255.255.0,12h
dhcp-option=3,${GATEWAY_IP}
dhcp-option=6,${GATEWAY_IP}
server=127.0.0.1#5353
# Captive Portal Detection Triggering (Seamlessness)
address=/google.com/${GATEWAY_IP}
address=/gstatic.com/${GATEWAY_IP}
address=/apple.com/${GATEWAY_IP}
address=/w3.org/${GATEWAY_IP}
EOL

# --- 10. Start Services & Monitor ---
log_info "Starting services..."
hostapd "$PREFIX/etc/hostapd/hostapd.conf" -B
HOSTAPD_PID=$!
dnsmasq -C "$PREFIX/etc/dnsmasq.conf" -B
DNSMASQ_PID=$!
export GATEWAY_IP
python3 server.py &
PYTHON_PID=$!

sleep 2

# Monitor Loop (The Ghost Hotspot Fix)
log_info "Monitoring services..."
while true; do
    for pid in $HOSTAPD_PID $DNSMASQ_PID $PYTHON_PID $GOST_PID; do
        if ! kill -0 $pid 2>/dev/null; then
            log_error "Critical service (PID $pid) died! Restarting..."
            # Simple restart logic: exit and let user restart or expand this to auto-restart
            exit 1
        fi
    done
    sleep 3
done
