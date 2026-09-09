# Termux-Hotspot

> **SECURITY ADVISORY:** This software creates network infrastructure that can potentially be exploited for phishing attacks, unauthorized device access, or malicious application distribution. Exercise extreme caution and understand all security implications before deployment.

![License](https://img.shields.io/badge/license-CC0--1.0-green)
![Termux](https://img.shields.io/badge/Termux-Required-blue)
![Root Required](https://img.shields.io/badge/Root-Required-red)

## 📖 About

**Termux-Hotspot** is a high-performance networking utility that transforms an Android device into a fully functional Wireless Access Point (AP) with a customizable Captive Portal and DNS-based Adblocking.

It automates the entire process of setting up `hostapd`, `dnsmasq`, and a Python-based authentication server, tailored for the latest Android and Termux environments.

## ✨ Features (Latest Optimizations)

*   **Dynamic WAN Interface:** Automatically detects your internet source (Cellular, USB Tethering, or Secondary Wi-Fi) instead of hardcoding `eth0`.
*   **Built-in DNS Adblocking:** Uses a self-hosted `gost` DNS proxy with **Quad9** (primary) and **Cloudflare** (fallback) upstreams to block ads and trackers at the network level.
*   **QoS & Bandwidth Limiting:** Implements **CAKE** QDisc (Common Applications Kept Enhanced) for bufferbloat mitigation, with a robust fallback to `iptables` for devices lacking advanced kernel support.
*   **High-Performance Tuning:** Includes optimized `hostapd` parameters (`beacon_int`, `dtim_period`) to reduce CPU overhead and improve stability.
*   **Modern Python 3.11+ Compatibility:** Captive portal uses `urllib.parse` instead of deprecated `cgi`.
*   **Automatic Dependency Installation:** Installs `hostapd`, `dnsmasq`, `iptables`, and `curl` automatically if missing.

## 🛠️ Prerequisites

*   **Termux:** Install from [F-Droid](https://f-droid.org/packages/com.termux/) (Play Store version requires API workarounds).
*   **Root Access:** Required for interface manipulation and binding to port 80.
*   **Wi-Fi Adapter:** Must support AP (Access Point) mode.

## 🚀 Installation & Deployment

1.  **Clone the Repository:**
    ```bash
    pkg install git
    git clone https://github.com/Argantor91/Termux-Hotspot.git
    cd Termux-Hotspot
    ```

2.  **Make Script Executable:**
    ```bash
    chmod +x hotspot.sh
    ```

3.  **Run as Root:**
    ```bash
    tsu ./hotspot.sh
    ```
    *(Note: Ensure you are running the script as root, not just using `sudo` inside the script, as Termux's `tsu` is the standard for root privileges.)*

## ⚙️ Configuration

Upon running, the script will prompt you for:
*   **SSID:** The name of your Hotspot.
*   **Password:** The Wi-Fi password.
*   **Channel:** The Wi-Fi channel (Default: 7).

The script will automatically:
1.  Download the latest adblock list (hagezi/light).
2.  Install missing dependencies.
3.  Configure the network interfaces and IP forwarding.
4.  Start the Captive Portal on port 8080 and redirect port 80 traffic to it.

## 🛡️ Security & Hardening

*   **Adblocking:** Clients will see blocked domains resolve to `127.0.0.1`.
*   **Gateway IP:** The gateway is permanently set to `192.168.1.1` for consistency.
*   **Firewall:** Basic NAT and Forward rules are applied. Advanced QoS rules are added if supported.

## 🐛 Troubleshooting

*   **"No default route found":** Ensure you have an active internet connection (Cellular Data or USB Tethering) before starting the script.
*   **"Port 80 busy":** If `python3` fails to bind to port 80, ensure no other service (like a web server) is running. The script attempts to redirect port 80 to the captive portal on port 8080.
*   **No Internet for Clients:** Check if `net.ipv4.ip_forward` is enabled. The script uses `sysctl -w net.ipv4.ip_forward=1` to ensure it stays active.

## 📄 License

This project is licensed under the **CC0 1.0 Universal** License. You are free to use, modify, and redistribute the code for any purpose, including commercial use, without attribution.
