# LuCI App for AdGuard Home DNS Lookup (OpenWrt)

🌍 [نسخه فارسی (Persian)](README-FA.md)

A blazing fast, native OpenWrt LuCI plugin to automatically resolve CDN and cloud domains and sync their localized IP addresses directly into **AdGuard Home's DNS rewrites**.

## 💡 The Idea
AdGuard Home is a powerful DNS sinkhole, but mapping wildcard CDN domains to specific localized IPs (for bypassing geo-blocks or optimizing routing via Passwall/SmartDNS) usually requires heavy Python scripts or manual configurations. 

This plugin solves this by using **native shell scripts (`sh`) and OpenWrt's UCI system**. It reads your specified domains, resolves them concurrently using OpenWrt's internal routing, and safely injects the IP blocks directly into `AdGuardHome.yaml` in under a second—without needing Python or any heavy dependencies!

## ✨ Features
- **Zero Heavy Dependencies**: Pure Shell and Lua. No Python needed.
- **Blazing Fast**: Uses Bash parallel background jobs (`&`) to resolve hundreds of domains simultaneously.
- **Native OpenWrt UI**: Seamlessly integrates into LuCI (`Services -> ADG DNS Lookup`).
- **UCI Standard**: Domain lists are managed elegantly using OpenWrt's native UCI configuration system instead of messy text files.
- **Built-in Cron**: Schedule automatic IP updates (e.g., Every 3 Hours, Daily) to keep CDN IPs fresh.
- **Pre-filled Extensive Lists**: Comes out of the box with extensive, categorized domain lists for Cloudflare, Fastly, Google, Meta, Microsoft, AWS, and more!
- **Safe YAML Injection**: Uses precision `awk`/`sed` text markers to inject rewrites without corrupting your AdGuard configuration.

## 🚀 Easy Installation (One-Line Script)
Run this command in your OpenWrt terminal to download and install the latest compiled package automatically:
```sh
# For OpenWrt 23.05 and older (.ipk)
wget -qO- https://github.com/USERNAME/luci-app-adg-dnslookup/releases/latest/download/install.sh | sh

# For OpenWrt 24.xx+ (.apk)
wget -qO- https://github.com/USERNAME/luci-app-adg-dnslookup/releases/latest/download/install-apk.sh | sh
```
*(Note: Replace USERNAME with your actual GitHub username after the release is published)*

## 🛠️ Step-by-Step Build Guide (Compile from Source)
If you prefer to compile the package yourself using the official OpenWrt SDK:

1. **Pull the OpenWrt SDK Docker image** (adjust the version based on your router's architecture, e.g., `x86_64`):
   ```sh
   docker pull openwrt/sdk:x86-64-23.05.0
   ```
2. **Run the SDK container**:
   ```sh
   docker run --rm -it openwrt/sdk:x86-64-23.05.0 bash
   ```
3. **Clone the repository into the SDK's package folder**:
   ```sh
   cd package
   git clone https://github.com/USERNAME/luci-app-adg-dnslookup.git
   cd ..
   ```
4. **Select the package in menuconfig**:
   ```sh
   make menuconfig
   # Go to LuCI -> 3. Applications -> luci-app-adg-dnslookup and press 'M' to build as a module
   ```
5. **Compile the package**:
   ```sh
   make package/luci-app-adg-dnslookup/compile -j$(nproc) V=s
   ```
6. **Retrieve your package**:
   The compiled `.ipk` (or `.apk` for newer SDKs) will be located in `bin/packages/*/base/`. Copy it to your router and install via `opkg install` or `apk add`.

## 📂 Code Structure
- `/Makefile`: Standard OpenWrt package build definitions.
- `/luasrc/`: Contains the LuCI frontend logic (`controller` for the menu, `model/cbi` for the UI forms).
- `/root/etc/config/adg_dnslookup`: The UCI configuration file storing settings and domain lists.
- `/root/etc/init.d/adg_dnslookup`: The procd init script managing the cron schedules.
- `/root/usr/bin/adg-sync.sh`: The core shell engine responsible for parallel DNS resolution and YAML injection.
