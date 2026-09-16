# Termux-Hotspot v10.3 (Repository Finality)

> **SECURITY ADVISORY:** This software creates network infrastructure that can potentially be exploited for phishing, unauthorized device access, or malicious application distribution. It dynamically modifies SELinux states and network routing tables.

![Version](https://img.shields.io/badge/version-10.3-blue)
![License](https://img.shields.io/badge/license-CC0--1.0-green)
![Termux](https://img.shields.io/badge/Termux-Required-blue)
![Root Required](https://img.shields.io/badge/Root-Required-red)
![Android 12+](https://img.shields.io/badge/Android-12%2B-green)

## 📖 About

**Termux-Hotspot v10.3** is a production-grade, state-aware network subsystem for rooted Android. It transforms your device into a secure Wireless Access Point with a **built-in Captive Portal**, **DNS-based Adblocking**, **NAT Routing**, and **QoS** support.

Unlike previous iterations, v10.3 is engineered specifically for **Android 12+**, utilizing `iptables-nft` compatible "Jump Chains" and dynamic SELinux handling to ensure stability across fragmented OEM kernels.

## ✨ Features (v10.3 Architecture)

*   **Android 12 `nftables` Compatible:** Uses dedicated `TERMUX_HOTSPOT_FWD` and `TERMUX_HOTSPOT_POST` jump chains to prevent routing collisions with native Android tethering or third-party firewalls (e.g., AFWall+).
*   **SELinux State Awareness:** Dynamically captures the current SELinux mode. If `Enforcing`, it switches to `Permissive` to allow `hostapd` `nl80211` binding, and **restores** the original state upon exit.
*   **Built-in Captive Portal:** Integrated Python3-based authentication server (`server.py`) with `portal.html` template support. Redirects port 80 traffic securely to port 8080.
*   **Resilient DNS Proxy (`gost`):** Implements a dual-stack upstream fallback (`TLS` then `UDP`) to bypass ISP port 853 blocks automatically.
*   **Captive Portal DNS Spoofing:** Automatically spoofs `connectivitycheck.gstatic.com` and other probes to force the "Sign in to network" popup on modern Android/iOS devices.
*   **Soft QoS Dependency:** `tc` is optional. If unsupported or missing, the hotspot functions normally without QoS restrictions.
*   **Surgical Cleanup:** Uses `ip addr del` (surgical removal) instead of `flush` to preserve IPv6 link-local addresses and Android's `WifiService` state.
*   **Phantom Process Killer Resilience:** Designed to run alongside Android's foreground service monitor, with a robust watchdog to restart daemons on failure.

## 🛠️ Prerequisites

*   **Termux:** Install from [F-Droid](https://f-droid.org/packages/com.termux/) (Play Store version requires API workarounds).
*   **Root Access:** Required for interface manipulation and binding to ports.
*   **Wi-Fi Adapter:** Must support AP (Access Point) mode (Realtek, Broadcom, or Qualcomm chips).

## 🚀 Installation & Deployment

### 1. Environment Setup

```bash
pkg install git hostapd dnsmasq iptables iproute2 coreutils python3
