# Termux-Hotspot v10.3 (Repository Finality)

> **SECURITY ADVISORY:** This software creates network infrastructure that can potentially be exploited for phishing, unauthorized device access, or malicious application distribution. It dynamically modifies SELinux states and network routing tables.

![Version](https://img.shields.io/badge/version-10.3-blue)
![License](https://img.shields.io/badge/license-CC0--1.0-green)
![Termux](https://img.shields.io/badge/Termux-Required-blue)
![Root Required](https://img.shields.io/badge/Root-Required-red)
![Android 12+](https://img.shields.io/badge/Android-12%2B-green)

## 📖 About

**Termux-Hotspot v10.3** is a production-grade, state-aware network subsystem for rooted Android. It transforms your device into a secure Wireless Access Point with a **built-in Captive Portal**, **DNS-based Adblocking**, **NAT Routing**, and **QoS** support.

Engineered specifically for **Android 12+**, it utilizes `iptables-nft` compatible "Jump Chains", dynamic SELinux handling, and automatic `wpa_supplicant` radio lock release to ensure stability across fragmented OEM kernels.

## ✨ Features (v10.3 Architecture)

*   **Issue #3 Resolution (Radio Lock Release):** Automatically detects if Android's native Wi-Fi is ON and uses `svc wifi disable` to release the `wlan0` interface from `wpa_supplicant`, preventing `nl80211` bind failures.
*   **Android 12 `nftables` Compatible:** Uses dedicated `TERMUX_HOTSPOT_FWD` and `TERMUX_HOTSPOT_POST` jump chains to prevent routing collisions with native Android tethering or third-party firewalls (e.g., AFWall+).
*   **SELinux State Awareness:** Dynamically captures the current SELinux mode. If `Enforcing`, it switches to `Permissive` to allow `hostapd` `nl80211` binding, and **restores** the original state upon exit.
*   **Built-in Captive Portal:** Integrated Python3-based authentication server (`server.py`) with OS-probe interception (302 Redirects) to force modern iOS/Android devices to trigger the automatic "Sign in to network" popup.
*   **Resilient DNS Proxy (`gost`):** Implements a dual-stack upstream fallback (`TLS` then `UDP`) to bypass ISP port 853 blocks automatically.
*   **Soft QoS Dependency:** `tc` is optional. If unsupported or missing, the hotspot functions normally without QoS restrictions.
*   **Surgical Cleanup:** Uses `ip addr del` (surgical removal) instead of `flush` to preserve IPv6 link-local addresses and Android's `WifiService` state.

## 🛠️ Prerequisites

*   **Termux:** Install from [F-Droid](https://f-droid.org/packages/com.termux/).
*   **Root Access:** Required for interface manipulation and binding to ports.
*   **Wi-Fi Adapter:** Must support AP (Access Point) mode.

## 🚀 Installation & Deployment

### 1. Environment Setup

```bash
pkg install git root-repo
pkg install hostapd dnsmasq iptables iproute2 coreutils python3

2. Phantom Process Killer (Android 12+ Mandatory)
Run this once via ADB or Root Shell to prevent the OS from terminating the watchdog loop:
bash

1
3. Deployment
bash

123456
⚙️ Configuration
Upon running, the script will prompt for:
SSID: Network name (Raw input supports special characters).
Password: WPA2 Passphrase (Min 8 chars). This password is used for both Wi-Fi and the Captive Portal.
Channel: Wi-Fi channel (Default: 7).
The script will automatically:
Disable Android's native Wi-Fi to claim the radio.
Generate hostapd.conf and securely save the Wi-Fi password to $PREFIX/tmp/hp_pass (chmod 600).
Start the Python3 Captive Portal (server.py) on port 8080.
Configure the network interfaces, IP forwarding, and DNS spoofing for captive portal detection.
Start the gost DNS proxy.
🐛 Troubleshooting
"No default route found": Ensure you have an active internet connection (Cellular Data or USB Tethering) before starting the script.
Captive Portal Not Popping Up: The script automatically spoofs connectivitycheck.gstatic.com and captive.apple.com. If it still doesn't pop up, manually visit http://10.0.0.1:8080 in a browser.
Hostapd Fails to Start: Ensure no other app is using the Wi-Fi radio. The script attempts to kill wpa_supplicant locks via svc wifi disable, but some aggressive OEM skins may require you to manually turn off Wi-Fi in settings first.
