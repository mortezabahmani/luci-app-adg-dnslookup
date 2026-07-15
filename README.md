<div align="center">

<img src="https://raw.githubusercontent.com/mortezabahmani/luci-app-adg-dnslookup/main/docs/logo.png" width="80" alt="ADG DNS Lookup Logo">

# luci-app-adg-dnslookup

**Professional LuCI plugin for AdGuard Home DNS Rewrite Sync**

[![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05%20|%2024.10-00B4FF?logo=openwrt&logoColor=white)](https://openwrt.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mortezabahmani/luci-app-adg-dnslookup?color=blue)](https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest)
[![Architecture](https://img.shields.io/badge/arch-all-lightgrey)](https://github.com/mortezabahmani/luci-app-adg-dnslookup)

🇮🇷 [نسخه فارسی](README-FA.md)

</div>

---

## 💡 The Problem

AdGuard Home is a powerful DNS sinkhole, but mapping CDN and cloud-provider domains to their **local or region-specific IPs** (for bypass routing via Passwall, SmartDNS, or similar tools) requires either:

- A heavy Python script running every hour, or
- Manual, error-prone edits to `AdGuardHome.yaml`

**There's a better way.**

---

## ✨ Solution

This plugin resolves your chosen domains using any DNS server (local or remote), then **atomically injects the discovered IPs** into AdGuard Home's `rewrites` block in under a second — no Python, no external packages, just pure **POSIX shell** and **OpenWrt UCI**.

```
┌─────────────────────────────────────────────────────────┐
│                     LuCI Web UI                         │
│  ┌───────────┐  ┌──────────────┐  ┌────────────────┐   │
│  │ Dashboard │  │   Settings   │  │  List Manager  │   │
│  └─────┬─────┘  └──────┬───────┘  └───────┬────────┘   │
│        │               │                  │             │
└────────┼───────────────┼──────────────────┼─────────────┘
         │               │                  │
         ▼               ▼                  ▼
    AJAX API ──────► UCI Config ◄──── Domain Lists (UCI)
         │
         ▼
    adg-sync.sh  (parallel nslookup)
         │
         ▼
    AdGuardHome.yaml  ← atomic awk injection
         │
         ▼
    /etc/init.d/adguardhome reload
```

---

## 🚀 Features

| Feature | Description |
|---|---|
| ⚡ **Blazing Fast** | Parallel `nslookup` with background jobs (`&`). 300 domains resolved in ~3s. |
| 🎨 **Professional UI** | Custom LuCI template (not plain CBI). Dark/light mode, animated sync badge. |
| 📊 **Live Dashboard** | Domain count, IPs injected, last-run status — all AJAX, no page reload. |
| 📋 **Live Log Viewer** | Color-coded log levels (INFO/WARN/ERROR/OK) with auto-scroll. |
| 🗂️ **UCI List Manager** | Add/remove categories and domains natively via UCI — no flat text files. |
| 🔄 **Auto-Sync (Cron)** | Built-in cron schedule: 1h / 3h / 6h / 12h / daily. |
| 🛡️ **Safe Injection** | Precision `awk` markers — never corrupts your AdGuard config. |
| 📦 **Zero Dependencies** | Pure shell + Lua. No Python, no Node, no extras. |
| 📋 **Pre-filled Lists** | 700+ domains across 9 categories: Google, Meta, Microsoft, CDN, Dev, Social, Streaming, Cloud, Cloudflare. |

---

## 📦 Installation

### Option 1 — One-line Smart Installer (Recommended)

Run this on your OpenWrt router terminal. It **auto-detects** your OpenWrt version and architecture, then downloads and installs the correct package format (`ipk` or `apk`):

```sh
wget -qO- https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest/download/install.sh | sh
```

> **Requires:** `wget` (pre-installed on all OpenWrt), internet access on router.

### Option 2 — Manual Download

Visit the [Releases page](https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest) and download the correct file:

| File | OpenWrt Version | Package Manager |
|---|---|---|
| `luci-app-adg-dnslookup_*_all.ipk` | ≤ 23.05 | `opkg` |
| `luci-app-adg-dnslookup_*_all.apk` | ≥ 24.10 | `apk` |

Then install:

```sh
# For IPK (OpenWrt ≤ 23.05)
opkg update && opkg install /tmp/luci-app-adg-dnslookup_*_all.ipk

# For APK (OpenWrt ≥ 24.10)
apk add --allow-untrusted /tmp/luci-app-adg-dnslookup_*_all.apk
```

---

## 🗂️ Domain Categories (Pre-installed)

| Category | Count | Includes |
|---|---|---|
| `google` | 57 | Gmail, Drive, Maps, YouTube APIs, Firebase, Gemini |
| `meta` | 33 | Facebook, Instagram, WhatsApp, Threads, Messenger |
| `microsoft` | 55 | Office 365, Teams, Azure, OneDrive, Bing, LinkedIn |
| `cloudflare` | 14 | CF DNS, Workers, Pages, Radar |
| `cdn` | 61 | Fastly, Akamai, jsDelivr, AWS CloudFront, Azure CDN |
| `cloud` | 103 | AWS, GCP, Azure, DigitalOcean, Hetzner, Vultr |
| `dev` | 269 | GitHub, GitLab, npm, PyPI, Docker Hub, VS Code, JetBrains |
| `social` | 52 | Twitter/X, Discord, Reddit, Telegram, Signal, Snapchat |
| `streaming` | 51 | YouTube, Netflix, Spotify, Twitch, Vimeo, Apple TV |

> All lists are fully editable from the **List Manager** tab in the LuCI UI.

---

## 🔧 Configuration Reference

The plugin stores all configuration in `/etc/config/adg_dnslookup` using OpenWrt's native UCI system.

### Main Section (`config adg_dnslookup 'main'`)

| UCI Key | Type | Default | Description |
|---|---|---|---|
| `enabled` | bool | `1` | Enable/disable the sync service |
| `adg_config_path` | string | `/etc/AdGuardHome.yaml` | Path to AdGuardHome config file |
| `custom_dns` | string | `127.0.0.1` | DNS server for domain resolution |
| `schedule` | string | `disabled` | Cron schedule (`1h`, `3h`, `6h`, `12h`, `daily`, `disabled`) |
| `domain_lists` | list | `google meta` | Space-separated list of active categories |

### Domain List Sections (`config domain_list 'name'`)

```
config domain_list 'my_custom_list'
    list domain 'example.com'
    list domain 'cdn.example.com'
    list domain 'api.example.com'
```

### Manual UCI Commands

```sh
# Enable the service
uci set adg_dnslookup.main.enabled=1 && uci commit adg_dnslookup

# Change DNS server to Cloudflare
uci set adg_dnslookup.main.custom_dns=1.1.1.1 && uci commit adg_dnslookup

# Set schedule to every 6 hours
uci set adg_dnslookup.main.schedule=6h && uci commit adg_dnslookup
/etc/init.d/adg_dnslookup restart

# Run sync manually
/usr/bin/adg-sync.sh

# View live log
tail -f /var/log/adg_dnslookup.log
```

---

## 🛠️ Build from Source

### Prerequisites

- macOS / Linux host
- [Docker](https://docs.docker.com/get-docker/) or [Colima](https://github.com/abiosoft/colima) (for M1 Mac)
- Git

### Step 1 — Clone the repository

```sh
git clone https://github.com/mortezabahmani/luci-app-adg-dnslookup.git
cd luci-app-adg-dnslookup
```

### Step 2 — Build IPK (OpenWrt ≤ 23.05, OPKG)

Pull the official OpenWrt SDK image. Replace `x86-64` with your router's target architecture:

```sh
# Common architectures:
# x86-64, ath79-generic, ramips-mt7621, ipq40xx-generic, mediatek-filogic

docker pull openwrt/sdk:x86-64-23.05.5

docker run --rm -it \
  -v $(pwd):/tmp/pkg \
  openwrt/sdk:x86-64-23.05.5 \
  bash -c '
    cd /home/build/openwrt
    cp -r /tmp/pkg package/luci-app-adg-dnslookup
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    make defconfig
    make package/luci-app-adg-dnslookup/compile -j$(nproc) V=s 2>&1
    find bin/packages -name "*.ipk" | grep adg
  '
```

The `.ipk` file will appear in `bin/packages/*/base/`.

### Step 3 — Build APK (OpenWrt ≥ 24.10)

```sh
docker pull openwrt/sdk:x86-64-SNAPSHOT

docker run --rm -it \
  -v $(pwd):/tmp/pkg \
  openwrt/sdk:x86-64-SNAPSHOT \
  bash -c '
    cd /home/build/openwrt
    cp -r /tmp/pkg package/luci-app-adg-dnslookup
    ./scripts/feeds update -a
    ./scripts/feeds install -a
    make defconfig
    make package/luci-app-adg-dnslookup/compile -j$(nproc) V=s 2>&1
    find bin/packages -name "*.apk" | grep adg
  '
```

### Step 4 — Alternative: Quick Local Build (all architecture, no SDK)

The included build script creates a valid `.ipk` without the full SDK:

```sh
bash scripts/build_local.sh
# Output: luci-app-adg-dnslookup_*_all.ipk
```

---

## 📂 Repository Structure

```
luci-app-adg-dnslookup/
├── Makefile                          # OpenWrt package build definition
├── scripts/
│   ├── install.sh                    # Smart one-line installer
│   └── build_local.sh                # Local IPK build script
├── luasrc/
│   ├── controller/
│   │   └── adg_dnslookup.lua         # LuCI menu + AJAX API endpoints
│   └── view/
│       └── adg_dnslookup/
│           └── main.htm              # Custom UI template (HTML/CSS/JS)
└── root/
    ├── etc/
    │   ├── config/
    │   │   └── adg_dnslookup         # UCI config (domain lists + settings)
    │   └── init.d/
    │       └── adg_dnslookup         # procd init + cron management
    └── usr/
        └── bin/
            └── adg-sync.sh           # Core sync engine (parallel shell)
```

---

## 🤝 Contributing

Pull requests are welcome! For major changes, please open an issue first to discuss what you would like to change.

1. Fork the repository
2. Create your feature branch: `git checkout -b feature/my-feature`
3. Commit your changes: `git commit -m 'feat: add my feature'`
4. Push to the branch: `git push origin feature/my-feature`
5. Open a Pull Request

---

## 📄 License

[MIT](LICENSE) © 2024 mortezabahmani
