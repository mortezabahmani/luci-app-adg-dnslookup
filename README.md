<div align="center">

```text
╷  ╷ ╷┌─╴╷   ┌─┐┌─┐┌─┐   ┌─┐╶┬┐┌─╴  ╶┬┐┌┐╷┌─┐╷  ┌─┐┌─┐╷┌ ╷ ╷┌─┐
│  │ ││  │╶─╴├─┤├─┘├─┘╶─╴├─┤ │││╶┐╶─╴│││└┤└─┐│  │ ││ │├┴┐│ │├─┘
└─╴└─┘└─╴╵   ╵ ╵╵  ╵     ╵ ╵╶┴┘└─┘  ╶┴┘╵ ╵└─┘└─╴└─┘└─┘╵ ╵└─┘╵  
```

# luci-app-adg-dnslookup

**Professional LuCI plugin for AdGuard Home DNS Rewrite Sync**

[![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05%20|%2024.10-00B4FF?logo=openwrt&logoColor=white)](https://openwrt.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mortezabahmani/luci-app-adg-dnslookup?color=blue)](https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest)

🇮🇷 [نسخه فارسی](README-FA.md)

</div>

---

## 💡 The Problem

AdGuard Home is a powerful DNS sinkhole, but mapping CDN and cloud-provider domains to their **local or region-specific IPs** (for bypass routing via Passwall, SmartDNS, or similar tools) requires either:

- A heavy Python script making thousands of API calls, or
- Manual, error-prone edits to the AdGuardHome config

**There's a better way.**

---

## ✨ Solution

This plugin resolves your chosen domains using any DNS server (local or remote), then **pushes the discovered IPs directly into AdGuard Home via its REST API** — no Python, no file path headaches, just pure **POSIX shell** and **OpenWrt UCI**.

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
    /www/adg_dnslookup.txt (Hosts file generation)
         │
         ▼
    AdGuardHome REST API  ← /control/filtering/add_url
```

---

## 🚀 Features

| Feature | Description |
|---|---|
| ⚡ **Blazing Fast** | Parallel `nslookup` with background jobs (`&`). 300 domains resolved in ~3s. |
| 🔌 **API-Based** | Pushes rewrites via AdGuardHome REST API — no YAML file editing, no path guessing. |
| 🎨 **Professional UI** | Custom LuCI template. Dark/light mode, animated sync badge. |
| 📊 **Live Dashboard** | Domain count, IPs injected, last-run status — all AJAX, no page reload. |
| 📋 **Live Log Viewer** | Color-coded log levels (INFO/WARN/ERROR/OK) with auto-scroll. |
| 🗂️ **UCI List Manager** | Add/remove categories and domains natively via UCI. |
| 🔄 **Auto-Sync (Cron)** | Built-in cron schedule: 1h / 3h / 6h / 12h / daily. |
| 🛡️ **Safe Sync** | Tracks previously pushed rewrites and cleans them before re-pushing. |
| 📋 **Pre-filled Lists** | 700+ domains across 9 categories: Google, Meta, Microsoft, CDN, Dev, Social, Streaming, Cloud, Cloudflare. |

---

## 📦 Installation

### OpenWrt ≤ 23.05 (opkg)

```sh
opkg update
opkg install curl bind-dig
curl -L -o /tmp/luci-app-adg-dnslookup.ipk https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest/download/luci-app-adg-dnslookup_3.0.5-1_all.ipk
opkg install /tmp/luci-app-adg-dnslookup.ipk
rm /tmp/luci-app-adg-dnslookup.ipk
service rpcd restart
```

### OpenWrt ≥ 24.10 (apk)

```sh
apk update
apk add curl bind-dig
curl -L -o /tmp/luci-app-adg-dnslookup.apk https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest/download/luci-app-adg-dnslookup_3.0.5-1_all.apk
apk add --allow-untrusted /tmp/luci-app-adg-dnslookup.apk
rm /tmp/luci-app-adg-dnslookup.apk
service rpcd restart
```

> **Note:** `curl` is required for downloading packages and for the DoH DNS protocol. `bind-dig` is optional and only needed for TCP DNS resolution.

---

## 🔧 Configuration

After installation, navigate to **Services → ADG DNS Lookup** in LuCI.

### Settings

| Field | Default | Description |
|---|---|---|
| **AdGuardHome API URL** | `http://127.0.0.1:3000` | Base URL of your AdGuardHome web interface |
| **Username** | *(empty)* | AdGuardHome login username |
| **Password** | *(empty)* | AdGuardHome login password |
| **DNS Protocol** | `UDP` | Protocol for resolving domains (`UDP` / `TCP` / `DoH`) |
| **DNS Server / URL** | `127.0.0.1` | DNS server IP or DoH URL |
| **Auto-Sync** | `Disabled` | Cron schedule: 1h / 3h / 6h / 12h / daily |

### UCI Reference

All configuration is stored in `/etc/config/adg_dnslookup`:

```
config adg_dnslookup 'main'
    option enabled '1'
    option adg_url 'http://127.0.0.1:3000'
    option adg_user 'admin'
    option adg_pass 'your_password'
    option custom_dns '127.0.0.1'
    option dns_protocol 'udp'
    option schedule 'disabled'
    list domain_lists 'google'
    list domain_lists 'meta'
```

### Manual CLI Commands

```sh
# Enable the service
uci set adg_dnslookup.main.enabled=1 && uci commit adg_dnslookup

# Set AdGuardHome credentials
uci set adg_dnslookup.main.adg_url='http://127.0.0.1:3000'
uci set adg_dnslookup.main.adg_user='admin'
uci set adg_dnslookup.main.adg_pass='mypassword'
uci commit adg_dnslookup

# Run sync manually
/usr/bin/adg-sync.sh

# View live log
tail -f /var/log/adg_dnslookup.log
```

---

## 🗂️ Pre-installed Domain Categories

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

> All lists are fully editable from the **List Manager** tab in LuCI.

---

## 🛠️ Build from Source

### Prerequisites

- macOS / Linux
- [Docker](https://docs.docker.com/get-docker/)
- Git

### Clone

```sh
git clone https://github.com/mortezabahmani/luci-app-adg-dnslookup.git
cd luci-app-adg-dnslookup
```

### Build IPK (OpenWrt ≤ 23.05)

```sh
bash scripts/build_local.sh
```

### Build APK (OpenWrt ≥ 24.10)

Use Docker with Alpine:

```sh
docker run --rm -v $(pwd):/work alpine:latest sh -c '
  apk add abuild openssl
  # ... (see scripts/build_local.sh for the full procedure)
'
```

---

## 📂 Project Structure

```
luci-app-adg-dnslookup/
├── Makefile                          # OpenWrt package definition
├── scripts/
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
            └── adg-sync.sh           # Core sync engine (API-based)
```

---

## 🤝 Contributing

Pull requests are welcome! For major changes, please open an issue first.

---

## 📄 License

[MIT](LICENSE) © 2024 mortezabahmani
