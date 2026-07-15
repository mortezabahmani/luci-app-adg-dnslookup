#!/bin/sh
# ADG DNS Lookup — Smart Installer
# Detects router architecture + OpenWrt version, downloads the correct package.
#
# Usage (run on your OpenWrt router):
#   wget -qO- https://github.com/mortezabahmani/luci-app-adg-dnslookup/releases/latest/download/install.sh | sh

set -e

REPO="mortezabahmani/luci-app-adg-dnslookup"
PKG_NAME="luci-app-adg-dnslookup"
RELEASES_BASE="https://github.com/${REPO}/releases/latest/download"

echo "╔══════════════════════════════════════════════╗"
echo "║   ADG DNS Lookup — Smart Installer           ║"
echo "╚══════════════════════════════════════════════╝"
echo ""

# ── Detect OpenWrt version ────────────────────────────────────────────────────
if [ ! -f /etc/openwrt_release ]; then
    echo "[ERROR] This script must be run on an OpenWrt router."
    exit 1
fi

. /etc/openwrt_release
OWRT_VERSION="${DISTRIB_RELEASE:-unknown}"
echo "[INFO] OpenWrt version : $OWRT_VERSION"

# ── Detect architecture ───────────────────────────────────────────────────────
ARCH=$(uname -m 2>/dev/null || echo "unknown")
echo "[INFO] Architecture    : $ARCH"

# ── Determine package format ──────────────────────────────────────────────────
# OpenWrt 24.10+ uses APK; anything before uses IPK/OPKG
USE_APK=0
MAJOR=$(echo "$OWRT_VERSION" | cut -d. -f1)
if [ "$MAJOR" -ge 24 ] 2>/dev/null; then
    USE_APK=1
fi

if [ "$USE_APK" = "1" ]; then
    PKG_EXT="apk"
    PKG_FILE="${PKG_NAME}_1.2.0-1_all.apk"
    INSTALL_CMD="apk add --allow-untrusted"
else
    PKG_EXT="ipk"
    PKG_FILE="${PKG_NAME}_1.2.0-1_all.ipk"
    INSTALL_CMD="opkg install"
fi

echo "[INFO] Package format  : $PKG_EXT"
echo "[INFO] Package file    : $PKG_FILE"
echo ""

# ── Download ──────────────────────────────────────────────────────────────────
DL_URL="${RELEASES_BASE}/${PKG_FILE}"
TMP_PKG="/tmp/${PKG_FILE}"

echo "[INFO] Downloading from:"
echo "       $DL_URL"
echo ""

if ! wget -q --show-progress -O "$TMP_PKG" "$DL_URL" 2>/dev/null; then
    # Fallback: wget without --show-progress (busybox)
    if ! wget -q -O "$TMP_PKG" "$DL_URL"; then
        echo "[ERROR] Download failed. Check your internet connection."
        rm -f "$TMP_PKG"
        exit 1
    fi
fi

echo "[OK] Download complete."

# ── Install Dependencies ────────────────────────────────────────────────────────
echo "[INFO] Installing dependencies (curl, bind-dig)..."
if [ "$USE_APK" = "1" ]; then
    apk update -q || true
    apk add curl bind-dig -q || true
else
    opkg update >/dev/null 2>&1 || true
    opkg install curl bind-dig >/dev/null 2>&1 || true
fi

# ── Install ───────────────────────────────────────────────────────────────────
echo "[INFO] Installing package..."

if $INSTALL_CMD "$TMP_PKG"; then
    echo ""
    echo "╔══════════════════════════════════════════════╗"
    echo "║  ✓  Installation successful!                 ║"
    echo "║                                              ║"
    echo "║  Navigate to: Services → ADG DNS Lookup      ║"
    echo "╚══════════════════════════════════════════════╝"
else
    echo "[ERROR] Installation failed."
    rm -f "$TMP_PKG"
    exit 1
fi

rm -f "$TMP_PKG"
