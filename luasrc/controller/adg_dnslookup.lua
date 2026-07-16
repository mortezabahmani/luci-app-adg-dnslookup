module("luci.controller.adg_dnslookup", package.seeall)

local http = require "luci.http"
local sys  = require "luci.sys"
local fs   = require "nixio.fs"
local json = require "luci.jsonc"
local uci  = require "luci.model.uci".cursor()

function index()
    if not fs.access("/etc/config/adg_dnslookup") then return end

    local e = entry({"admin", "services", "adg_dnslookup"},
        template("adg_dnslookup/main"), _("ADG DNS Lookup"), 60)
    e.dependent = true

    entry({"admin", "services", "adg_dnslookup", "api_status"},   call("api_status"),  nil).leaf = true
    entry({"admin", "services", "adg_dnslookup", "api_logs"},     call("api_logs"),    nil).leaf = true
    entry({"admin", "services", "adg_dnslookup", "api_clear_logs"}, call("api_clear_logs"), nil).leaf = true
    entry({"admin", "services", "adg_dnslookup", "api_sync"},     call("api_sync"),    nil).leaf = true
    entry({"admin", "services", "adg_dnslookup", "api_save"},     call("api_save"),    nil).leaf = true
    entry({"admin", "services", "adg_dnslookup", "api_test_dns"}, call("api_test_dns"), nil).leaf = true
    entry({"admin", "services", "adg_dnslookup", "api_lists"},    call("api_lists"),   nil).leaf = true
    entry({"admin", "services", "adg_dnslookup", "api_list_op"},  call("api_list_op"), nil).leaf = true
end

-- ─── Helpers ─────────────────────────────────────────────────────────────────

local function json_response(data)
    http.prepare_content("application/json")
    http.write(json.stringify(data))
end

local function get_uci_main(key, default)
    return uci:get("adg_dnslookup", "main", key) or default
end

-- ─── API: Status ─────────────────────────────────────────────────────────────

function api_status()
    local status_raw = fs.readfile("/var/run/adg_dnslookup.status") or ""
    local stats_raw  = fs.readfile("/var/run/adg_dnslookup.stats")  or "{}"

    local ok, stats = pcall(json.parse, stats_raw)
    if not ok then stats = {} end

    -- Count domains across all lists
    local total_domains = 0
    uci:foreach("adg_dnslookup", "domain_list", function(s)
        local domains = uci:get_list("adg_dnslookup", s[".name"], "domain")
        if domains then total_domains = total_domains + #domains end
    end)

    local enabled = get_uci_main("enabled", "0")
    local running = (sys.call("pgrep -f adg-sync.sh >/dev/null 2>&1") == 0)

    local badge = "disabled"
    if enabled == "1" then
        badge = running and "syncing" or "idle"
        if status_raw:match("Error") then badge = "error" end
        if status_raw:match("Success") then badge = "ok" end
    end

    local dns_list = uci:get_list("adg_dnslookup", "main", "dns_servers") or {}
    local dns_servers_str = table.concat(dns_list, "\n")

    json_response({
        badge         = badge,
        status_text   = status_raw:gsub("\n", ""),
        total_domains = total_domains,
        last_ip_count = stats.ip_count or 0,
        last_run      = stats.last_run or "",
        running       = running,
        enabled       = (enabled == "1"),
        schedule      = get_uci_main("schedule", "disabled"),
        adg_url       = get_uci_main("adg_url", "http://127.0.0.1:3000"),
        adg_user      = get_uci_main("adg_user", ""),
        adg_pass      = get_uci_main("adg_pass", ""),
        dns_servers   = dns_servers_str,
        dns_protocol  = get_uci_main("dns_protocol", "udp"),
    })
end

-- ─── API: Logs ────────────────────────────────────────────────────────────────

function api_logs()
    local log = fs.readfile("/var/log/adg_dnslookup.log") or "No log file found."
    json_response({ log = log })
end

function api_clear_logs()
    if http.getenv("REQUEST_METHOD") ~= "POST" then
        http.status(405, "Method Not Allowed")
        return
    end
    sys.call("> /var/log/adg_dnslookup.log")
    json_response({ ok = true })
end

-- ─── API: Manual Sync ────────────────────────────────────────────────────────

function api_sync()
    if http.getenv("REQUEST_METHOD") ~= "POST" then
        http.status(405, "Method Not Allowed")
        return
    end
    sys.call("/usr/bin/adg-sync.sh >/dev/null 2>&1 &")
    json_response({ ok = true, message = "Sync started" })
end

-- ─── API: Save Settings ──────────────────────────────────────────────────────

function api_save()
    if http.getenv("REQUEST_METHOD") ~= "POST" then
        http.status(405, "Method Not Allowed")
        return
    end
    local body = http.content()
    local ok, data = pcall(json.parse, body)
    if not ok or not data then
        http.status(400, "Bad Request")
        json_response({ ok = false, message = "Invalid JSON" })
        return
    end

    local allowed = { enabled=1, adg_url=1, adg_user=1, adg_pass=1, schedule=1, dns_protocol=1 }
    for k, v in pairs(data) do
        if allowed[k] then
            uci:set("adg_dnslookup", "main", k, tostring(v))
        end
    end
    
    if data.dns_servers then
        local server_list = {}
        for s in string.gmatch(data.dns_servers, "[^\r\n]+") do
            local s_trim = s:match("^%s*(.-)%s*$")
            if s_trim ~= "" then table.insert(server_list, s_trim) end
        end
        uci:set_list("adg_dnslookup", "main", "dns_servers", server_list)
    end
    
    uci:commit("adg_dnslookup")

    -- Reload cron via init.d
    sys.call("/etc/init.d/adg_dnslookup restart >/dev/null 2>&1")
    json_response({ ok = true })
end

-- ─── API: Test DNS ────────────────────────────────────────────────────────────

function api_test_dns()
    if http.getenv("REQUEST_METHOD") ~= "POST" then
        http.status(405, "Method Not Allowed")
        return
    end
    local body = http.content()
    local ok, data = pcall(json.parse, body)
    if not ok or not data or not data.server then
        http.status(400, "Bad Request")
        json_response({ ok = false, message = "Invalid JSON" })
        return
    end

    local server = data.server
    local protocol = get_uci_main("dns_protocol", "udp")
    local test_cmd = ""
    
    if protocol == "doh" then
        test_cmd = string.format("curl -s -m 2 -H 'accept: application/dns-json' '%s?name=google.com&type=A' >/dev/null 2>&1", server:gsub("'", ""))
    elseif protocol == "tcp" then
        test_cmd = string.format("dig +tcp +short @'%s' google.com +time=2 >/dev/null 2>&1", server:gsub("'", ""))
    else
        test_cmd = string.format("nslookup -timeout=2 google.com '%s' >/dev/null 2>&1", server:gsub("'", ""))
    end

    local res = sys.call(test_cmd)
    json_response({ ok = (res == 0) })
end

-- ─── API: List all domain lists ──────────────────────────────────────────────

function api_lists()
    local lists = {}
    uci:foreach("adg_dnslookup", "domain_list", function(s)
        local name    = s[".name"]
        local domains = uci:get_list("adg_dnslookup", name, "domain") or {}
        table.insert(lists, { name = name, domains = domains, count = #domains })
    end)
    table.sort(lists, function(a, b) return a.name < b.name end)
    json_response({ lists = lists })
end

-- ─── API: List operations (add/delete category, add/delete domain) ────────────

function api_list_op()
    if http.getenv("REQUEST_METHOD") ~= "POST" then
        http.status(405, "Method Not Allowed")
        return
    end
    local body = http.content()
    local ok, data = pcall(json.parse, body)
    if not ok or not data then
        http.status(400, "Bad Request")
        json_response({ ok = false })
        return
    end

    local action = data.action or ""

    if action == "add_category" then
        local name = data.name:gsub("[^%w_%-]", ""):lower()
        if name == "" then
            json_response({ ok = false, message = "Invalid category name" })
            return
        end
        uci:section("adg_dnslookup", "domain_list", name, {})
        uci:commit("adg_dnslookup")
        json_response({ ok = true, name = name })

    elseif action == "delete_category" then
        uci:delete("adg_dnslookup", data.name)
        uci:commit("adg_dnslookup")
        json_response({ ok = true })

    elseif action == "add_domain" then
        local name   = data.category or ""
        local domain = data.domain:gsub("%s+", ""):lower()
        if name == "" or domain == "" then
            json_response({ ok = false, message = "Missing params" })
            return
        end
        uci:add_list("adg_dnslookup", name, "domain", domain)
        uci:commit("adg_dnslookup")
        json_response({ ok = true })

    elseif action == "delete_domain" then
        local name   = data.category or ""
        local domain = data.domain or ""
        local domains = uci:get_list("adg_dnslookup", name, "domain") or {}
        local new = {}
        for _, d in ipairs(domains) do
            if d ~= domain then table.insert(new, d) end
        end
        uci:set("adg_dnslookup", name, "domain", new)
        uci:commit("adg_dnslookup")
        json_response({ ok = true })

    else
        http.status(400, "Bad Request")
        json_response({ ok = false, message = "Unknown action: " .. action })
    end
end
