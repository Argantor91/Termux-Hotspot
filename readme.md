# Termux-Hotspot (updated readme, no updated files)

![license](https://img.shields.io/badge/license-CC0--1.0-green)

> **SECURITY ADVISORY:** This software creates network infrastructure that can potentially be exploited for phishing attacks, unauthorized device access, or malicious application distribution. Exercise extreme caution and understand all security implications before deployment. This tool hasn't been tested either

>  *Compilation page for Termux: [termux/termux-packages#10160](https://github.com/termux/termux-packages/issues/10160)*

## 1. Project Architecture Overview

Termux-Hotspot is an networking utility that enables Android devices to function as a wireless access points with authentication capabilities. The solution leverages low-level networking subsystems to implement:

- **Wireless Access Point (AP)** functionality via hostapd
- **DHCP service** for network address assignment via dnsmasq
- **Network Address Translation (NAT)** for internet traffic routing
- **Captive Portal Authentication** system for connection authorization

The system architecture employs a multi-layered approach:

```
┌───────────────────────────────────────────┐
│            Termux Environment             │
├───────────┬───────────────┬───────────────┤
│  hostapd  │    dnsmasq    │  Python HTTP  │
│  (802.11) │  (DHCP/DNS)   │    Server     │
├───────────┴───────────────┴───────────────┤
│         Linux Networking Subsystem        │
│   (IP Tables, Routing, Interface Mgmt)    │
├───────────────────────────────────────────┤
│        Android Network Infrastructure      │
└───────────────────────────────────────────┘
```

## 2. Technical Prerequisites

### 2.1 System Requirements

- Android device with Termux installed (available on [F-Droid](https://f-droid.org/packages/com.termux/))
- Root access (required for network interface manipulation)
- Wi-Fi adapter supporting AP (Access Point) mode
- Minimum 50MB free storage
- Active internet connection (cellular data or secondary Wi-Fi adapter)

### 2.2 Required Packages

- **hostapd**: Access point daemon for IEEE 802.11 management
- **dnsmasq**: Lightweight DHCP and caching DNS server
- **iptables**: Administrative tool for IPv4 packet filtering and NAT
- **python**: Runtime environment for the captive portal system

## 3. Installation Procedure

### 3.1 Repository Acquisition

```bash
# Clone the repository
git clone https://github.com/CPScript/Termux-Hotspot.git
cd Termux-Hotspot

# Set execution permissions
chmod +x software/hotspot.sh
```

### 3.2 Package Dependencies

```bash
# Install required packages
pkg update
pkg install root-repo
pkg install tsu hostapd dnsmasq python

# Verify installations
command -v hostapd >/dev/null 2>&1 || echo "hostapd not installed"
command -v dnsmasq >/dev/null 2>&1 || echo "dnsmasq not installed"
command -v python >/dev/null 2>&1 || echo "python not installed"
```

## 4. Implementation & Deployment

### 4.1 Automated Deployment

The repository provides an automated configuration script for rapid deployment:

```bash
# Navigate to software directory
cd software

# Execute the main script with root privileges
sudo ./hotspot.sh
```

During execution, you'll be prompted to configure:
- SSID (network name)
- Authentication passphrase
- Wireless channel selection

### 4.2 Manual Implementation Process

For environments requiring customized deployment, follow this systematic implementation procedure:

#### 4.2.1 Interface Configuration

First, identify your device's wireless interface and internet-connected interface:

```bash
# List network interfaces
ip link

# Identify default route interface
ip route | grep default
```

#### 4.2.2 Create Virtual AP Interface

```bash
# Create virtual AP interface (if supported)
iw dev wlan0 interface add wlan0ap type __ap

# If virtual interface creation fails, use physical interface
# Set interface in AP mode
ip link set wlan0 down
ip link set wlan0 up
```

#### 4.2.3 Configure hostapd

Create a configuration file at `/etc/hostapd/hostapd.conf`:

```
interface=wlan0ap      # Or wlan0 if virtual interface not supported
driver=nl80211
ssid=YourNetworkName   # Customize this
hw_mode=g
channel=7              # Select optimal channel for your environment
wmm_enabled=0
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=2
wpa_passphrase=YourStrongPassword  # Customize this
wpa_key_mgmt=WPA-PSK
wpa_pairwise=TKIP
rsn_pairwise=CCMP
```

#### 4.2.4 Configure DHCP Service

Create a configuration file at `/etc/dnsmasq.conf`:

```
interface=wlan0ap      # Must match hostapd interface
dhcp-range=192.168.1.2,192.168.1.100,255.255.255.0,12h
```

#### 4.2.5 Initialize Network Services

Start the required services:

```bash
# Kill any existing instances
killall hostapd dnsmasq 2>/dev/null

# Start hostapd
hostapd /etc/hostapd/hostapd.conf &

# Start dnsmasq
dnsmasq &
```

#### 4.2.6 Configure Network Routing

Enable IP forwarding and configure NAT:

```bash
# Enable IP forwarding
echo 1 > /proc/sys/net/ipv4/ip_forward

# Detect internet-connected interface
WAN_IF=$(ip route | grep default | awk '{print $5}')

# Set up NAT routing
iptables -t nat -A POSTROUTING -o $WAN_IF -j MASQUERADE
iptables -A FORWARD -i wlan0ap -o $WAN_IF -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -A FORWARD -i $WAN_IF -o wlan0ap -j ACCEPT
```

#### 4.2.7 Deploy Captive Portal (Optional)

For environments requiring authentication:

```bash
# Start the captive portal server
python server.py &
```

## 5. Security Considerations

### 5.1 Network Security Vulnerabilities

This implementation presents several security considerations:

- **Unauthorized Access**: Default configurations may allow unauthorized network access
- **Network Traffic Visibility**: User traffic passes through your device
- **Resource Constraints**: Heavy usage may affect device performance and battery life
- **Regulatory Compliance**: Operating an access point may be subject to local regulations

### 5.2 Hardening Recommendations

For production deployments, implement these hardening measures:

1. Configure MAC address filtering in hostapd
2. Implement WPA2-Enterprise with RADIUS authentication
3. Enable packet inspection and firewall rules
4. Segregate guest network traffic
5. Implement bandwidth limiting and QoS
6. Maintain regular security patches

## 6. Troubleshooting Procedures

| Issue | Diagnostic Approach | Resolution Strategy |
|-------|---------------------|---------------------|
| hostapd fails to start | Check `hostapd -dd /etc/hostapd/hostapd.conf` for detailed errors | Verify interface exists, no conflicting Wi-Fi services, and correct driver support |
| No IP addresses assigned | Examine `logcat -b all \| grep dnsmasq` | Verify dnsmasq is running and configured correctly |
| No internet connectivity | Check `ip route` and `iptables -t nat -L -v` | Ensure IP forwarding is enabled and NAT rules are correct |
| Clients can connect but no portal | Check `netstat -tulpn \| grep python` | Verify the Python server is running and accessible |

## 7. Advanced Configuration

### 7.1 Persistent Configuration

For persistent deployment across reboots:

```bash
# Create init script
cat > /data/local/hotspot_init.sh <<EOF
#!/system/bin/sh
# Startup script for hotspot
/path/to/hostapd /etc/hostapd/hostapd.conf &
/path/to/dnsmasq &
echo 1 > /proc/sys/net/ipv4/ip_forward
iptables -t nat -A POSTROUTING -o [WAN_INTERFACE] -j MASQUERADE
EOF

# Make executable
chmod +x /data/local/hotspot_init.sh

# Add to init.rc or use Magisk for persistent startup
```

### 7.2 Performance Optimization

For high-density environments:

```
# hostapd performance tuning
beacon_int=100
dtim_period=2
rts_threshold=2347
fragm_threshold=2346
```
---

© 2025 Termux-Hotspot | Maintained by [CPScript](https://github.com/CPScript) (**Not Tested**)
