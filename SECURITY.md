# 🛡️ Security Guide & Advisory

**Termux-Hotspot** is a high-performance networking utility that manipulates low-level Linux kernel subsystems. Because it manages network interfaces, routing, and DNS, it requires high privileges and introduces specific security considerations.

## ⚠️ Critical Warning: Root Privileges

This project requires **Root Access** (via `tsu` or `sudo`). 
*   **The Risk:** The script executes commands that modify the kernel's networking stack (e.g., `iptables`, `ip`, `sysctl`, `hostapd`). 
*   **The Implication:** A mistake in the script or a malicious modification could potentially disrupt your device's primary connectivity, create unintended firewall holes, or expose your device to the local network. Always audit the `hotspot.sh` script before running it as root.

## 🌐 Network Security & Topology

### 1. Captive Portal & HTTP Traffic
The built-in Captive Portal uses a Python-based web server.
*   **Unencrypted Traffic:** By default, the portal and redirection (Port 80 $\rightarrow$ 8080) operate over **HTTP**, not HTTPS. 
*   **Security Tip:** Do not use the captive portal to transmit highly sensitive information (like passwords) unless you implement TLS (HTTPS) within the `server.py` configuration. Traffic between the client and the hotspot is susceptible to local Man-in-the-Middle (MITM) sniffing.

### 2. DNS Proxy & Adblocking (`gost`)
Your project uses a `gost` proxy for DNS adblocking and upstream routing (Quad9/Cloudflare).
*   **Trust Model:** All DNS queries from connected clients are routed through this proxy. Security relies on the integrity of the `gost` binary and the reliability of the upstream DNS providers.
*   **Adblocking:** The adblocking mechanism works by resolving malicious domains to `127.0.0.1`. This is a highly efficient way to block ads at the network level without heavy client-side overhead.

### 3. Network Isolation
When the Hotspot is active, the Android device acts as a **Layer 3 Gateway**.
*   **Client-to-Client Communication:** By default, clients on the same hotspot can communicate with each other. If you require strict isolation (where clients can only see the gateway), advanced `iptables` isolation rules must be applied.
*   **NAT (Network Address Translation):** The script uses NAT to allow clients to share your internet connection. This masks client IP addresses from the wide-area network (WAN) but makes the Android device the single point of failure/control.

## 🚀 Advanced Feature Security

### Dynamic WAN Detection
The script automatically detects your internet source (Cellular, USB, or Wi-Fi).
*   **Security Note:** The script identifies the default route to bridge the connection. Ensure that the interface being used as the WAN source is trusted.

### QoS & CAKE (Bufferbloat Mitigation)
Using `CAKE` or `iptables` for bandwidth limiting improves performance but manages traffic locally.
*   **Performance vs. Security:** QoS helps prevent a single client from saturating the link (a form of local "Denial of Service"), ensuring more stable connectivity for all devices.

## 🛠️ Best Practices for Users

1.  **Audit the Code:** Before running `tsu ./hotspot.sh`, review the `software/` directory to ensure the commands match your expectations.
2.  **Use Trusted Upstreams:** When configuring DNS, stick to reputable providers like **Quad9** or **Cloudflare** (as implemented) to ensure DNSSEC-like reliability.
3.  **Clean Shutdown:** Always stop the hotspot using the intended method to ensure `iptables` rules and `dnsmasq` processes are cleaned up, preventing "zombie" network configurations.
