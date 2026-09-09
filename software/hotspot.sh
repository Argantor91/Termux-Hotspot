#!/bin/bash

# Termux-Hotspot Production Build
# Features: Permanent Gateway IP, QoS (Cake/Iptables), GOST DNS Adblocking, Performance Tuning

# --- Color Codes ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# --- Core Configuration (Permanent Local IP) ---
# This is the IP that clients will see as their "Gateway"
GATEWAY_IP="192.168.1.1"
SUBNET="192.168.1.0/24"
SUBNET_MASK="192.168.1.0" # For netmask calculation in dnsmasq if needed

# --- Helper Functions ---
log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# --- 1. Dependency Check ---
check_deps() {
    local missing=0
    for cmd in hostapd dnsmasq iptables curl; do
        if ! command -v $cmd &>/dev/null; then
            log_error "Missing dependency: $cmd. Install with: pkg install $cmd"
            missing=1
        fi
    done
    if [ $missing -eq 1 ]; then exit 1; fi
}

check_deps

# --- 2. Root & Environment Check ---
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root (use tsu or sudo)."
    exit 1
fi

# --- 3. User Configuration ---
log_info "Configuring Hotspot..."
read -p "Enter SSID (Network Name): " SSID
read -sp "Enter Password: " PASSWORD
echo ""
read -p "Enter Channel (default 7 for 2.4GHz): " CHANNEL
CHANNEL=${CHANNEL:-7}

# --- 4. Dynamic Interface Detection ---
AP_IF=$(ip link show | grep -E "^[0-9]+:" | grep -oP '^\d+:\s+\w+' | grep -E '(wlan|wifi)' | head -1 | awk '{print $2}' | tr -d ':')
if [ -z "$AP_IF" ]; then
    AP_IF="wlan0"
    log_warn "Could not auto-detect Wi-Fi interface, defaulting to $AP_IF"
fi

WAN_IF=$(ip route | grep default | awk '{print $5}')
if [ -z "$WAN_IF" ]; then
    log_error "No default route found. Ensure you are connected to the internet (Cellular or USB Tethering)."
    exit 1
fi
log_info "WAN Interface: $WAN_IF | AP Interface: $AP_IF"

# --- 5. Bandwidth Limiting (QoS) with Redundancy ---
log_info "Configuring QoS/Bandwidth Limiting..."
if command -v tc &>/dev/null; then
    tc qdisc replace dev $WAN_IF root cake 2>/dev/null
    if [ $? -eq 0 ]; then
        log_info "CAKE QDisc enabled on $WAN_IF (Bufferbloat mitigation)"
        tc class add dev $WAN_IF parent cake: classid cake:default htb rate 10mbit 2>/dev/null
    else
        log_warn "CAKE unavailable on $WAN_IF. Falling back to iptables rate limit..."
        iptables -A FORWARD -i $AP_IF -o $WAN_IF -m limit --limit 5/second --limit-burst 20 -j ACCEPT
    fi
else
    log_warn "tc (Traffic Control) not found. Using iptables rate limit fallback."
    iptables -A FORWARD -i $AP_IF -o $WAN_IF -m limit --limit 5/second --limit-burst 20 -j ACCEPT
fi

# --- 6. Clean Up Existing Services ---
trap 'echo -e "\n${YELLOW}Stopping Hotspot...${NC}"; killall -9 hostapd dnsmasq python3 gost 2>/dev/null; log_info "Done!"' EXIT
killall -9 hostapd dnsmasq python3 gost 2>/dev/null

# --- 7. Network & IP Forwarding Setup ---
log_info "Setting up Network Routing..."
# Use permanent GATEWAY_IP for the interface and DHCP
iptables -t nat -F POSTROUTING 2>/dev/null
iptables -F FORWARD 2>/dev/null

ip addr add ${GATEWAY_IP}/24 dev $AP_IF 2>/dev/null
sysctl -w net.ipv4.ip_forward=1
iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE
iptables -A FORWARD -i $AP_IF -o $WAN_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $WAN_IF -o $AP_IF -j ACCEPT
# Captive Portal Redirect: Send port 80 traffic to Python server (8080)
iptables -t nat -A PREROUTING -i $AP_IF -p tcp --dport 80 -j REDIRECT --to-port 8080

# --- 8. Upstream DNS & Adblocking (GOST) ---
ADBLOCK_LIST="$PREFIX/adblock.list"
log_info "Downloading Adblock list from hagezi..."
curl -sL -o "$ADBLOCK_LIST" "https://raw.githubusercontent.com/hagezi/dns-blocklists/master/light.txt" 2>/dev/null || \
curl -sL -o "$ADBLOCK_LIST" "https://raw.githubusercontent.com/hagezi/dns-blocklists/master/facebook.txt" 2>/dev/null

if ! command -v gost &>/dev/null; then
    log_info "Installing GOST (DNS Proxy)..."
    ARCH=$(uname -m)
    if [ "$ARCH" == "aarch64" ]; then
        curl -sL -o "$PREFIX/bin/gost" "https://github.com/ginuerzh/gost/releases/latest/download/gost-linux-arm64"
    elif [ "$ARCH" == "arm" ] || [ "$ARCH" == "armv7l" ]; then
        curl -sL -o "$PREFIX/bin/gost" "https://github.com/ginuerzh/gost/releases/latest/download/gost-linux-armv7"
    else
        curl -sL -o "$PREFIX/bin/gost" "https://github.com/ginuerzh/gost/releases/latest/download/gost-linux-amd64"
    fi
    chmod +x "$PREFIX/bin/gost"
fi

gost -L dns://127.0.0.1:5353?adblock=$ADBLOCK_LIST&forward=9.9.9.9:53,1.1.1.1:53 --log-level=error &
log_info "GOST DNS Proxy started on port 5353"

# --- 9. Configure hostapd (with Performance Tuning) ---
cat > /etc/hostapd/hostapd.conf <<EOL
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
logger_syslog=-1
logger_syslog_level=0

# 7.2 Performance Optimization
beacon_int=100
dtim_period=2
rts_threshold=2347
fragm_threshold=2346
EOL

# --- 10. Configure dnsmasq (with GOST and Fallbacks) ---
cat > /etc/dnsmasq.conf <<EOL
interface=$AP_IF
dhcp-range=${GATEWAY_IP}+2,${GATEWAY_IP}+100,255.255.255.0,12h
dhcp-option=3,${GATEWAY_IP}
dhcp-option=6,${GATEWAY_IP}
server=127.0.0.1#5353
server=9.9.9.9
server=1.1.1.1
EOL

# --- 11. Start Services ---
log_info "Starting Services..."
# Export Gateway IP so the Python server knows its own address
export HOTSPOT_PASSWORD=$PASSWORD
export GATEWAY_IP=$GATEWAY_IP 

hostapd /etc/hostapd/hostapd.conf -B
dnsmasq -C /etc/dnsmasq.conf -B
python3 server.py &
sleep 2

log_info "Hotspot is Ready!"
echo -e "SSID: $SSID"
echo -e "Password: $PASSWORD"
echo -e "AP IP (Gateway): ${GATEWAY_IP}"
echo -e "WAN IP: $WAN_IF"
echo -e "Connect to the network and visit any website to see the Captive Portal."
