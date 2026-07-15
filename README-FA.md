<div align="center">

<img src="https://raw.githubusercontent.com/mortezabahmani/luci-app-adg-dnslookup/main/docs/logo.png" width="80" alt="ADG DNS Lookup Logo">

# luci-app-adg-dnslookup

**افزونه حرفه‌ای LuCI برای همگام‌سازی DNS Rewrite در AdGuard Home**

[![OpenWrt](https://img.shields.io/badge/OpenWrt-23.05%20|%2024.10-00B4FF?logo=openwrt&logoColor=white)](https://openwrt.org)
[![License: MIT](https://img.shields.io/badge/License-MIT-green.svg)](LICENSE)
[![Release](https://img.shields.io/github/v/release/mortezabahmani/luci-app-adg-dnslookup?color=blue)](https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest)
[![Architecture](https://img.shields.io/badge/arch-all-lightgrey)](https://github.com/mortezabahmani/luci-app-adg-dnslookup)

🌍 [English Version](README.md)

</div>

---

## 💡 مشکل

AdGuard Home یک سرویس قدرتمند مدیریت DNS است، اما برای اینکه دامنه‌های CDN و سرویس‌های ابری را به **IPهای محلی یا منطقه‌ای** (جهت روتینگ از طریق Passwall، SmartDNS یا ابزارهای مشابه) هدایت کنیم، معمولاً نیاز است:

- یا یک اسکریپت سنگین Python هر ساعت اجرا شود، یا
- به صورت دستی و مستعد خطا فایل `AdGuardHome.yaml` ویرایش شود

**راهی بهتر وجود دارد.**

---

## ✨ راه‌حل

این افزونه، دامنه‌های انتخابی شما را با استفاده از هر DNS سرور دلخواه (محلی یا ریموت) resolve می‌کند، سپس IPهای کشف‌شده را در کمتر از یک ثانیه به صورت **اتمیک** در بخش `rewrites` فایل AdGuard Home تزریق می‌کند — بدون Python، بدون پکیج‌های اضافی، فقط **Shell خالص** و **UCI بومی OpenWrt**.

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
    AdGuardHome.yaml  ← تزریق امن با awk
          │
          ▼
    /etc/init.d/adguardhome reload
```

---

## 🚀 ویژگی‌ها

| ویژگی | توضیح |
|---|---|
| ⚡ **فوق‌العاده سریع** | پردازش موازی با `nslookup` پس‌زمینه (`&`). ۳۰۰ دامنه در ~۳ ثانیه. |
| 🎨 **رابط کاربری حرفه‌ای** | تمپلیت سفارشی LuCI (نه CBI ساده). حالت تاریک/روشن، نشانگر متحرک سینک. |
| 📊 **داشبورد زنده** | تعداد دامنه، IPهای inject شده، وضعیت آخرین اجرا — همه AJAX، بدون بارگذاری مجدد. |
| 📋 **لاگ بلادرنگ** | سطوح لاگ با رنگ‌بندی (INFO/WARN/ERROR/OK) و اسکرول خودکار. |
| 🗂️ **مدیریت لیست UCI** | اضافه/حذف دسته‌بندی و دامنه به صورت بومی — بدون فایل‌های متنی. |
| 🔄 **همگام‌سازی خودکار** | زمان‌بندی cron داخلی: ۱ ساعت / ۳ ساعت / ۶ ساعت / ۱۲ ساعت / روزانه. |
| 🛡️ **تزریق ایمن** | نشانگرهای دقیق `awk` — هرگز فایل AdGuard شما خراب نمی‌شود. |
| 📦 **بدون پیش‌نیاز** | فقط Shell و Lua. بدون Python، بدون Node، بدون هیچ چیز اضافه. |
| 📋 **لیست‌های آماده** | بیش از ۷۰۰ دامنه در ۹ دسته‌بندی: Google، Meta، Microsoft، CDN، Dev، Social، Streaming، Cloud، Cloudflare. |

---

## 📦 نصب

### روش ۱ — اسکریپت نصب هوشمند یک خطی (توصیه‌شده)

این دستور را در ترمینال روتر OpenWrt اجرا کنید. به صورت **خودکار** ورژن OpenWrt و معماری شما را تشخیص می‌دهد و فرمت صحیح (`ipk` یا `apk`) را دانلود و نصب می‌کند:

```sh
wget -qO- https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest/download/install.sh | sh
```

> **نیازمند:** `wget` (پیش‌نصب در تمام نسخه‌های OpenWrt) و دسترسی اینترنت روتر.

### روش ۲ — دانلود دستی

از [صفحه Releases](https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest) فایل مناسب را دانلود کنید:

| فایل | ورژن OpenWrt | مدیریت پکیج |
|---|---|---|
| `luci-app-adg-dnslookup_*_all.ipk` | ≤ 23.05 | `opkg` |
| `luci-app-adg-dnslookup_*_all.apk` | ≥ 24.10 | `apk` |

سپس نصب کنید:

```sh
# برای IPK (OpenWrt ≤ 23.05)
opkg update && opkg install /tmp/luci-app-adg-dnslookup_*_all.ipk

# برای APK (OpenWrt ≥ 24.10)
apk add --allow-untrusted /tmp/luci-app-adg-dnslookup_*_all.apk
```

---

## 🗂️ دسته‌بندی‌های دامنه (پیش‌نصب)

| دسته‌بندی | تعداد | شامل |
|---|---|---|
| `google` | ۵۷ | Gmail، Drive، Maps، YouTube API، Firebase، Gemini |
| `meta` | ۳۳ | Facebook، Instagram، WhatsApp، Threads، Messenger |
| `microsoft` | ۵۵ | Office 365، Teams، Azure، OneDrive، Bing، LinkedIn |
| `cloudflare` | ۱۴ | CF DNS، Workers، Pages، Radar |
| `cdn` | ۶۱ | Fastly، Akamai، jsDelivr، AWS CloudFront، Azure CDN |
| `cloud` | ۱۰۳ | AWS، GCP، Azure، DigitalOcean، Hetzner، Vultr |
| `dev` | ۲۶۹ | GitHub، GitLab، npm، PyPI، Docker Hub، VS Code، JetBrains |
| `social` | ۵۲ | Twitter/X، Discord، Reddit، Telegram، Signal، Snapchat |
| `streaming` | ۵۱ | YouTube، Netflix، Spotify، Twitch، Vimeo، Apple TV |

> تمام لیست‌ها از طریق تب **List Manager** در رابط کاربری LuCI قابل ویرایش هستند.

---

## 🔧 مرجع پیکربندی

افزونه تمام تنظیمات را در `/etc/config/adg_dnslookup` با استفاده از سیستم بومی UCI در OpenWrt ذخیره می‌کند.

### بخش اصلی (`config adg_dnslookup 'main'`)

| کلید UCI | نوع | پیش‌فرض | توضیح |
|---|---|---|---|
| `enabled` | bool | `1` | فعال/غیرفعال کردن سرویس |
| `adg_config_path` | string | `/etc/AdGuardHome.yaml` | مسیر فایل تنظیمات AdGuardHome |
| `custom_dns` | string | `127.0.0.1` | DNS سرور برای resolve دامنه‌ها |
| `schedule` | string | `disabled` | زمان‌بندی cron (`1h`, `3h`, `6h`, `12h`, `daily`, `disabled`) |
| `domain_lists` | list | `google meta` | لیست دسته‌بندی‌های فعال |

### بخش‌های لیست دامنه (`config domain_list 'name'`)

```
config domain_list 'my_custom_list'
    list domain 'example.com'
    list domain 'cdn.example.com'
    list domain 'api.example.com'
```

### دستورات UCI دستی

```sh
# فعال کردن سرویس
uci set adg_dnslookup.main.enabled=1 && uci commit adg_dnslookup

# تغییر DNS سرور به Cloudflare
uci set adg_dnslookup.main.custom_dns=1.1.1.1 && uci commit adg_dnslookup

# تنظیم زمان‌بندی به هر ۶ ساعت
uci set adg_dnslookup.main.schedule=6h && uci commit adg_dnslookup
/etc/init.d/adg_dnslookup restart

# اجرای دستی sync
/usr/bin/adg-sync.sh

# مشاهده لاگ زنده
tail -f /var/log/adg_dnslookup.log
```

---

## 🛠️ بیلد از سورس

### پیش‌نیازها

- macOS / Linux
- [Docker](https://docs.docker.com/get-docker/) یا [Colima](https://github.com/abiosoft/colima) (برای Mac با تراشه M1)
- Git

### مرحله ۱ — کلون کردن ریپازیتوری

```sh
git clone https://github.com/mortezabahmani/luci-app-adg-dnslookup.git
cd luci-app-adg-dnslookup
```

### مرحله ۲ — بیلد IPK (OpenWrt ≤ 23.05، OPKG)

ایمیج SDK رسمی OpenWrt را pull کنید. `x86-64` را با معماری روتر خود جایگزین کنید:

```sh
# معماری‌های رایج:
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

فایل `.ipk` در مسیر `bin/packages/*/base/` ایجاد می‌شود.

### مرحله ۳ — بیلد APK (OpenWrt ≥ 24.10)

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

### مرحله ۴ — بیلد سریع محلی (بدون SDK)

اسکریپت build موجود یک فایل `.ipk` معتبر بدون نیاز به SDK کامل می‌سازد:

```sh
bash scripts/build_local.sh
# خروجی: luci-app-adg-dnslookup_*_all.ipk
```

---

## 📂 ساختار ریپازیتوری

```
luci-app-adg-dnslookup/
├── Makefile                          # تعریف پکیج OpenWrt
├── scripts/
│   ├── install.sh                    # اسکریپت نصب هوشمند
│   └── build_local.sh                # بیلد محلی IPK
├── luasrc/
│   ├── controller/
│   │   └── adg_dnslookup.lua         # منوی LuCI + API Endpoints
│   └── view/
│       └── adg_dnslookup/
│           └── main.htm              # تمپلیت سفارشی رابط کاربری
└── root/
    ├── etc/
    │   ├── config/
    │   │   └── adg_dnslookup         # کانفیگ UCI (لیست‌ها + تنظیمات)
    │   └── init.d/
    │       └── adg_dnslookup         # اسکریپت init و مدیریت cron
    └── usr/
        └── bin/
            └── adg-sync.sh           # موتور اصلی sync
```

---

## 🤝 مشارکت

درخواست‌های Pull Request خوش‌آمد هستند! برای تغییرات بزرگ، لطفاً ابتدا یک Issue باز کنید تا درباره آنچه می‌خواهید تغییر دهید بحث کنیم.

---

## 📄 مجوز

[MIT](LICENSE) © 2024 mortezabahmani

### پشتیبانی از پروتکل‌های مختلف DNS
از نسخه v1.2.0 به بعد، شما می‌توانید مستقیماً از داخل تنظیمات از بین پروتکل‌های UDP، TCP و DoH (DNS-over-HTTPS) برای استخراج IP دامنه‌ها استفاده کنید.
- **UDP:** از `nslookup` استاندارد استفاده می‌کند. سریع و سبک.
- **TCP:** از `bind-dig` برای رزولوشن قابل اتکاتر استفاده می‌کند.
- **DoH:** با استفاده از `curl` دامنه‌ها را به صورت کاملاً امن استخراج می‌کند (مثلاً `https://cloudflare-dns.com/dns-query`).
