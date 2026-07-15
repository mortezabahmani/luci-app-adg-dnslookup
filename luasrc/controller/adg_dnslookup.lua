module("luci.controller.adg_dnslookup", package.seeall)

function index()
    if not nixio.fs.access("/etc/config/adg_dnslookup") then
        return
    end

    entry({"admin", "services", "adg_dnslookup"}, cbi("adg_dnslookup/settings"), _("ADG DNS Lookup"), 60).dependent = true
end
