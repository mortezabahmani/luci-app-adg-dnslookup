include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for AdGuard Home DNS Lookup
LUCI_DEPENDS:=+luci-base +adguardhome
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-adg-dnslookup
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
