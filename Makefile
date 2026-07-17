include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for AdGuard Home DNS Lookup
LUCI_DESCRIPTION:=Automatically resolve CDN/cloud domain IPs and sync them into AdGuard Home DNS rewrites. Features a professional custom LuCI interface with dark mode, live logs, and animated sync.
LUCI_DEPENDS:=+luci-base +adguardhome +curl +bind-dig
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-adg-dnslookup
PKG_VERSION:=3.1.7
PKG_RELEASE:=1

PKG_LICENSE:=MIT
PKG_MAINTAINER:=mortezabahmani

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
$(eval $(call BuildPackage,$(PKG_NAME)))
