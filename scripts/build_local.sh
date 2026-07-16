#!/bin/bash
# Local build script — creates a valid .ipk without needing the full OpenWrt SDK
set -e
PKG_NAME="luci-app-adg-dnslookup"
PKG_VERSION="3.0.6"
PKG_RELEASE="1"
FULL_VER="${PKG_VERSION}-${PKG_RELEASE}"
SRC="$(cd "$(dirname "$0")/.." && pwd)"

WORKDIR=$(mktemp -d)
trap 'rm -rf "$WORKDIR"' EXIT

mkdir -p "$WORKDIR"/{data,control}
cp -r "$SRC/root/"* "$WORKDIR/data/"
mkdir -p "$WORKDIR/data/usr/lib/lua/luci"
cp -r "$SRC/luasrc/"* "$WORKDIR/data/usr/lib/lua/luci/"
chmod 755 "$WORKDIR/data/usr/bin/adg-sync.sh" 2>/dev/null || true

INSTALLED_SIZE=$(du -sk "$WORKDIR/data" | cut -f1)
cat > "$WORKDIR/control/control" << CTRL
Package: $PKG_NAME
Version: $FULL_VER
Depends: libc, luci-base, adguardhome, curl, bind-dig
License: MIT
Section: luci
Architecture: all
Installed-Size: $INSTALLED_SIZE
Description: LuCI support for AdGuard Home DNS Lookup
CTRL

echo "2.0" > "$WORKDIR/debian-binary"
cd "$WORKDIR/control" && tar --numeric-owner -czf ../control.tar.gz ./
cd "$WORKDIR/data"    && tar --numeric-owner -czf ../data.tar.gz ./
cd "$WORKDIR"         && tar --numeric-owner -czf "$SRC/${PKG_NAME}_${FULL_VER}_all.ipk" debian-binary control.tar.gz data.tar.gz

echo "✓ Built: $SRC/${PKG_NAME}_${FULL_VER}_all.ipk"
ls -lh "$SRC/${PKG_NAME}_${FULL_VER}_all.ipk"
