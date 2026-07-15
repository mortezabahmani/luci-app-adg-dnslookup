local fs = require "nixio.fs"

local m = Map("adg_dnslookup", translate("AdGuard Home DNS Lookup"),
    translate("Automatically resolve domains and sync them to AdGuard Home rewrites."))

-- Read last status
local status = "Never run or status file missing."
if fs.access("/var/run/adg_dnslookup.status") then
    status = fs.readfile("/var/run/adg_dnslookup.status") or status
end

-- Top-level Status Display (Dummy Section)
local s_status = m:section(SimpleSection)
s_status.template = "cbi/nullsection"
s_status.description = string.format("<strong>Status:</strong> %s", status)

-- TAB 1: General Settings
local s = m:section(TypedSection, "main", translate("General Settings"))
s.anonymous = true
s.addremove = false

o = s:option(Flag, "enabled", translate("Enable"))
o.rmempty = false

o = s:option(Value, "adg_config_path", translate("AdGuardHome Config Path"))
o.default = "/etc/AdGuardHome.yaml"
o.rmempty = false

o = s:option(Value, "custom_dns", translate("DNS Server for Resolution"))
o.default = "127.0.0.1"
o:value("127.0.0.1", translate("127.0.0.1 (Local Passwall/SmartDNS)"))
o:value("8.8.8.8", translate("8.8.8.8 (Google)"))
o:value("1.1.1.1", translate("1.1.1.1 (Cloudflare)"))
o.rmempty = false

o = s:option(ListValue, "schedule", translate("Update Schedule"))
o:value("disabled", translate("Disabled"))
o:value("3h", translate("Every 3 Hours"))
o:value("6h", translate("Every 6 Hours"))
o:value("daily", translate("Daily"))
o.rmempty = false

-- We need to manually parse the active domain_list sections to populate the domain_lists option
local list_names = {}
m.uci:foreach("adg_dnslookup", "domain_list", function(s)
    table.insert(list_names, s['.name'])
end)
table.sort(list_names)

o = s:option(DynamicList, "domain_lists", translate("Active Domain Lists"),
    translate("Select which domain lists will be queried during the sync."))
for _, name in ipairs(list_names) do
    o:value(name, name)
end

-- Manual Sync Button
o = s:option(Button, "sync_now", translate("Manual Sync"))
o.inputtitle = translate("Scan Now")
o.write = function()
    os.execute("/usr/bin/adg-sync.sh >/dev/null 2>&1 &")
end

-- TAB 2: List Manager (Native UCI List Management)
local s_mgr = m:section(TypedSection, "domain_list", translate("List Manager"),
    translate("Manage domain categories natively via UCI. You can create new categories and add/remove domains using the buttons below."))
s_mgr.addremove = true
s_mgr.anonymous = false
s_mgr.template = "cbi/tblsection" -- Display as a table of sections or standard section

local o_dom = s_mgr:option(DynamicList, "domain", translate("Domains"))
o_dom.rmempty = true

-- TAB 3: Logs
local s_log = m:section(TypedSection, "main", translate("Logs"))
s_log.anonymous = true

local o_log = s_log:option(TextValue, "_log", translate("Execution Log"))
o_log.rows = 20
o_log.readonly = true
o_log.cfgvalue = function(self, section)
    return fs.readfile("/var/log/adg_dnslookup.log") or "No log found."
end

return m
