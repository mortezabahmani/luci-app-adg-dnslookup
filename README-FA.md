<div align="center">

<img src="https://raw.githubusercontent.com/mortezabahmani/luci-app-adg-dnslookup/main/docs/logo.png" width="80" alt="ADG DNS Lookup Logo">

# luci-app-adg-dnslookup

**افزونه حرفه‌ای LuCI برای همگام‌سازی DNS Rewrite در AdGuard Home**

[![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05%20|%2024.10-00B4FF?logo=openwrt&logoColor=white)](https://openwrt.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mortezabahmani/luci-app-adg-dnslookup?color=blue)](https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest)

🌍 [English Version](README.md)

</div>

---

## 💡 مشکل

AdGuard Home یک سرویس قدرتمند مدیریت DNS است، اما برای اینکه دامنه‌های CDN و سرویس‌های ابری را به **IPهای محلی یا منطقه‌ای** (جهت روتینگ از طریق Passwall، SmartDNS یا ابزارهای مشابه) هدایت کنیم، معمولاً نیاز است:

- یک اسکریپت سنگین Python با هزاران درخواست API، یا
- ویرایش دستی و مستعد خطای فایل تنظیمات AdGuardHome

**راهی بهتر وجود دارد.**

---

## ✨ راه‌حل

این افزونه، دامنه‌های انتخابی شما را با استفاده از هر DNS سرور دلخواه resolve می‌کند، سپس IPهای کشف‌شده را **مستقیماً از طریق REST API ادگارد هوم** تزریق می‌کند — بدون Python، بدون نیاز به دانستن مسیر فایل‌ها، فقط **Shell خالص** و **UCI بومی OpenWrt**.

```
┌─────────────────────────────────────────────────────────┐
│                    رابط کاربری LuCI                     │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │  داشبورد     │  │  تنظیمات    │  │ مدیریت لیست │  │
│  └──────┬───────┘  └──────┬───────┘  └──────┬───────┘  │
│         │                 │                  │          │
└─────────┼─────────────────┼──────────────────┼──────────┘
          │                 │                  │
          ▼                 ▼                  ▼
     AJAX API ─────► UCI Config ◄─── لیست دامنه‌ها (UCI)
          │
          ▼
    adg-sync.sh  (nslookup موازی)
          │
          ▼
    AdGuardHome REST API  ← /control/rewrite/add
```

---

## 🚀 ویژگی‌ها

| ویژگی | توضیح |
|---|---|
| ⚡ **فوق‌العاده سریع** | پردازش موازی با `nslookup` پس‌زمینه. ۳۰۰ دامنه در ~۳ ثانیه. |
| 🔌 **مبتنی بر API** | رکوردها از طریق REST API ادگارد هوم ارسال می‌شوند — بدون ویرایش فایل YAML. |
| 🎨 **رابط حرفه‌ای** | تمپلیت سفارشی LuCI. حالت تاریک/روشن و نشانگر متحرک. |
| 📊 **داشبورد زنده** | تعداد دامنه، IPهای ثبت‌شده، وضعیت آخرین اجرا — AJAX بدون بارگذاری مجدد. |
| 📋 **لاگ بلادرنگ** | سطوح لاگ با رنگ‌بندی (INFO/WARN/ERROR/OK) و اسکرول خودکار. |
| 🗂️ **مدیریت لیست** | اضافه/حذف دسته‌بندی و دامنه به صورت بومی از طریق UCI. |
| 🔄 **همگام‌سازی خودکار** | زمان‌بندی cron: ۱ ساعت / ۳ ساعت / ۶ ساعت / ۱۲ ساعت / روزانه. |
| 🛡️ **سینک ایمن** | رکوردهای قبلی قبل از ارسال مجدد پاک می‌شوند. |
| 📋 **لیست‌های آماده** | بیش از ۷۰۰ دامنه در ۹ دسته‌بندی. |

---

## 📦 نصب

### OpenWrt ≤ 23.05 (opkg)

```sh
opkg update
opkg install curl bind-dig
curl -L -o /tmp/luci-app-adg-dnslookup.ipk https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest/download/luci-app-adg-dnslookup_2.1.0-1_all.ipk
opkg install /tmp/luci-app-adg-dnslookup.ipk
rm /tmp/luci-app-adg-dnslookup.ipk
service rpcd restart
```

### OpenWrt ≥ 24.10 (apk)

```sh
apk update
apk add curl bind-dig
curl -L -o /tmp/luci-app-adg-dnslookup.apk https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest/download/luci-app-adg-dnslookup_2.1.0-1_all.apk
apk add --allow-untrusted /tmp/luci-app-adg-dnslookup.apk
rm /tmp/luci-app-adg-dnslookup.apk
service rpcd restart
```

> **نکته:** `curl` برای دانلود پکیج و پروتکل DoH لازم است. `bind-dig` اختیاری و فقط برای حالت TCP نیاز است.

---

## 🔧 پیکربندی

بعد از نصب، از منوی **Services → ADG DNS Lookup** در LuCI استفاده کنید.

### تنظیمات

| فیلد | پیش‌فرض | توضیح |
|---|---|---|
| **AdGuardHome API URL** | `http://127.0.0.1:3000` | آدرس پنل وب AdGuardHome |
| **نام کاربری** | *(خالی)* | نام کاربری ورود به ادگارد هوم |
| **رمز عبور** | *(خالی)* | رمز عبور ورود به ادگارد هوم |
| **پروتکل DNS** | `UDP` | پروتکل resolve دامنه‌ها (`UDP` / `TCP` / `DoH`) |
| **سرور DNS** | `127.0.0.1` | آدرس IP یا URL سرور DNS |
| **سینک خودکار** | `غیرفعال` | زمان‌بندی cron |

### مرجع UCI

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

### دستورات CLI

```sh
# فعال کردن سرویس
uci set adg_dnslookup.main.enabled=1 && uci commit adg_dnslookup

# تنظیم اطلاعات ادگارد هوم
uci set adg_dnslookup.main.adg_url='http://127.0.0.1:3000'
uci set adg_dnslookup.main.adg_user='admin'
uci set adg_dnslookup.main.adg_pass='mypassword'
uci commit adg_dnslookup

# اجرای دستی
/usr/bin/adg-sync.sh

# مشاهده لاگ زنده
tail -f /var/log/adg_dnslookup.log
```

---

## 🗂️ دسته‌بندی‌های دامنه

| دسته‌بندی | تعداد | شامل |
|---|---|---|
| `google` | ۵۷ | Gmail، Drive، Maps، YouTube، Firebase، Gemini |
| `meta` | ۳۳ | Facebook، Instagram، WhatsApp، Threads، Messenger |
| `microsoft` | ۵۵ | Office 365، Teams، Azure، OneDrive، Bing، LinkedIn |
| `cloudflare` | ۱۴ | CF DNS، Workers، Pages، Radar |
| `cdn` | ۶۱ | Fastly، Akamai، jsDelivr، CloudFront، Azure CDN |
| `cloud` | ۱۰۳ | AWS، GCP، Azure، DigitalOcean، Hetzner، Vultr |
| `dev` | ۲۶۹ | GitHub، GitLab، npm، PyPI، Docker Hub، VS Code |
| `social` | ۵۲ | Twitter/X، Discord، Reddit، Telegram، Signal |
| `streaming` | ۵۱ | YouTube، Netflix، Spotify، Twitch، Vimeo |

> تمام لیست‌ها از تب **List Manager** در LuCI قابل ویرایش هستند.

---

## 🛠️ بیلد از سورس

### پیش‌نیازها

- macOS / Linux
- [Docker](https://docs.docker.com/get-docker/)
- Git

### کلون و بیلد

```sh
git clone https://github.com/mortezabahmani/luci-app-adg-dnslookup.git
cd luci-app-adg-dnslookup
bash scripts/build_local.sh
```

---

## 📂 ساختار پروژه

```
luci-app-adg-dnslookup/
├── Makefile                          # تعریف پکیج OpenWrt
├── scripts/
│   └── build_local.sh                # بیلد محلی IPK
├── luasrc/
│   ├── controller/
│   │   └── adg_dnslookup.lua         # API Endpoints
│   └── view/
│       └── adg_dnslookup/
│           └── main.htm              # رابط کاربری
└── root/
    ├── etc/
    │   ├── config/
    │   │   └── adg_dnslookup         # کانفیگ UCI
    │   └── init.d/
    │       └── adg_dnslookup         # اسکریپت init
    └── usr/
        └── bin/
            └── adg-sync.sh           # موتور سینک (مبتنی بر API)
```

---

## 🤝 مشارکت

Pull Request خوش‌آمد! برای تغییرات بزرگ ابتدا Issue باز کنید.

---

## 📄 مجوز

[MIT](LICENSE) © 2024 mortezabahmani
