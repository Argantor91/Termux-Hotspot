# Termux-Hotspot v10.3 (Repository Finality)

> **SECURITY ADVISORY:** This software creates network infrastructure that can potentially be exploited for phishing, unauthorized device access, or malicious application distribution. It dynamically modifies SELinux states and network routing tables.

![Version](https://img.shields.io/badge/version-10.3-blue)
![License](https://img.shields.io/badge/license-CC0--1.0-green)
![Termux](https://img.shields.io/badge/Termux-Required-blue)
![Root Required](https://img.shields.io/badge/Root-Required-red)
![Android 12+](https://img.shields.io/badge/Android-12%2B-green)

## 📖 About

**Termux-Hotspot v10.3** is a production-grade, state-aware network subsystem for rooted Android. It transforms your device into a secure Wireless Access Point with a **built-in Captive Portal**, **DNS-based Adblocking**, **NAT Routing**, and **QoS** support.

## ✨ Features (v10.3 Architecture)

*   **Android 12 `nftables` Compatible:** Uses dedicated `TERMUX_HOTSPOT_FWD` and `TERMUX_HOTSPOT_POST` jump chains.
*   **SELinux State Awareness:** Dynamically sets to Permissive for `hostapd` and restores original state on exit.
*   **Built-in Captive Portal:** Integrated Python3-based authentication server with DNS spoofing for automatic popup triggering.
*   **Resilient DNS Proxy (`gost`):** Dual-stack fallback (TLS + UDP) for ISP resilience.
*   **Soft QoS Dependency:** `tc` is optional; falls back gracefully.
*   **Surgical Cleanup:** Uses `ip addr del` to preserve IPv6/link-local states.

## 🚀 Aligned Deployment Steps

Follow these exact steps in order to ensure a clean installation on Android 12+.

### 1. Environment Preparation

Install all required dependencies via Termux package manager:
```bash
pkg update && pkg upgrade
pkg install git hostapd dnsmasq iptables iproute2 coreutils python3
