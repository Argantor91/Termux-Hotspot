# 🚀 Termux-Hotspot (High-Performance Edition)

Transform your Android device into a professional-grade Wireless Access Point (AP) with a built-in Captive Portal, DNS-based Adblocking, and advanced QoS.

## ✨ Features
*   **Dynamic WAN Detection:** Automatically bridges your Cellular or USB tethering to Wi-Fi.
*   **Adblocking:** Built-in `gost` DNS proxy using `hagezi` blocklists.
*   **Advanced QoS:** Implements **CAKE** (Bufferbloat mitigation) with `iptables` fallback.
*   **Captive Portal:** Integrated Python-based authentication server.
*   **Performance Tuned:** Optimized `hostapd` parameters for stability and low CPU usage.

## 🛠️ Installation

1. **Prerequisites:**
   * Termux (F-Droid version preferred)
   * Root Access (Required)
   * `pkg install hostapd dnsmasq iptables curl tsu`

2. **Setup:**
   ```bash
   git clone https://github.com/Argantor91/Termux-Hotspot.git
   cd Termux-Hotspot/software
   chmod +x hotspot.sh
   tsu ./hotspot.sh
   
