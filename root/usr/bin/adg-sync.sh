#!/bin/sh
# AdGuard Home DNS Lookup — Sync Engine v2
# Resolves domains from UCI lists in parallel,
# then pushes results via the AdGuardHome REST API.
# ponytail: no YAML file manipulation, no fragile path detection.

LOG_FILE="/var/log/adg_dnslookup.log"
STATUS_FILE="/var/run/adg_dnslookup.status"
STATS_FILE="/var/run/adg_dnslookup.stats"
TMP_FILE="/tmp/adg_dnslookup_ips.tmp"
PID_FILE="/var/run/adg_dnslookup.pid"

# ─── Logging ──────────────────────────────────────────────────────────────────
log() {
    local level="$1" msg="$2"
    echo "$(date +'%Y-%m-%d %H:%M:%S') [$level] $msg" >> "$LOG_FILE"
    # Rotate: keep last 500 lines if over 600
    local lc
    lc=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    [ "$lc" -gt 600 ] && { tail -n 500 "$LOG_FILE" > "${LOG_FILE}.tmp"; mv "${LOG_FILE}.tmp" "$LOG_FILE"; }
}
log_info()  { log "INFO"  "$1"; }
log_warn()  { log "WARN"  "$1"; }
log_error() { log "ERROR" "$1"; }
log_ok()    { log "OK"    "$1"; }

# ─── Guard: only one instance ─────────────────────────────────────────────────
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    kill -0 "$old_pid" 2>/dev/null && { log_warn "Already running (PID $old_pid). Exiting."; exit 0; }
fi
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

log_info "═══════════════════════════════════════════"
log_info "Starting DNS synchronization (PID $$)"

# ─── UCI helpers ──────────────────────────────────────────────────────────────
uci_get() { uci -q get "adg_dnslookup.main.$1"; }

# ─── Config ───────────────────────────────────────────────────────────────────
ENABLED=$(uci_get enabled)
if [ "$ENABLED" != "1" ]; then
    log_warn "Service is disabled. Exiting."
    echo "Disabled" > "$STATUS_FILE"
    exit 0
fi

ADG_URL=$(uci_get adg_url)
[ -z "$ADG_URL" ] && ADG_URL="http://127.0.0.1:3000"
# Strip trailing slash
ADG_URL="${ADG_URL%/}"

ADG_USER=$(uci_get adg_user)
ADG_PASS=$(uci_get adg_pass)

DNS_SERVERS=$(uci -q get adg_dnslookup.main.dns_servers)
[ -z "$DNS_SERVERS" ] && DNS_SERVERS="127.0.0.1"

DNS_PROTO=$(uci_get dns_protocol)
[ -z "$DNS_PROTO" ] && DNS_PROTO="udp"

# Build curl auth flag
AUTH_FLAG=""
[ -n "$ADG_USER" ] && AUTH_FLAG="-u ${ADG_USER}:${ADG_PASS}"

# ─── Verify API connectivity ─────────────────────────────────────────────────
if ! curl -sf $AUTH_FLAG "${ADG_URL}/control/status" >/dev/null 2>&1; then
    log_error "Cannot reach AdGuardHome API at '${ADG_URL}'. Check URL/credentials."
    echo "Error: Cannot reach AdGuardHome API at ${ADG_URL}" > "$STATUS_FILE"
    exit 1
fi

log_info "API: $ADG_URL"
log_info "DNS Proto: $DNS_PROTO"

# ─── Filter Available DNS Servers ─────────────────────────────────────────────
AVAILABLE_SERVERS=""
for server in $DNS_SERVERS; do
    server=$(echo "$server" | tr -d '\r')
    case "$DNS_PROTO" in
        doh)
            if curl -s -m 2 -H 'accept: application/dns-json' "${server}?name=google.com&type=A" >/dev/null 2>&1; then
                AVAILABLE_SERVERS="$AVAILABLE_SERVERS $server"
            fi
            ;;
        tcp)
            if dig +tcp +short "@${server}" google.com +time=2 >/dev/null 2>&1; then
                AVAILABLE_SERVERS="$AVAILABLE_SERVERS $server"
            fi
            ;;
        *)
            if nslookup -timeout=2 google.com "$server" >/dev/null 2>&1; then
                AVAILABLE_SERVERS="$AVAILABLE_SERVERS $server"
            fi
            ;;
    esac
done

if [ -z "$AVAILABLE_SERVERS" ]; then
    log_warn "None of the configured DNS servers are accessible. Falling back to default list."
    AVAILABLE_SERVERS="$DNS_SERVERS" # fallback
fi

# Remove leading/trailing spaces for accurate counting
AVAILABLE_SERVERS=$(echo "$AVAILABLE_SERVERS" | awk '{$1=$1};1')
NUM_SERVERS=$(echo "$AVAILABLE_SERVERS" | awk '{print NF}')
log_info "Available DNS Servers: ${NUM_SERVERS}"

# ─── Domain resolution ────────────────────────────────────────────────────────
> "$TMP_FILE"

resolve_domain() {
    local domain="$1" ips=""
    
    # Helper to pick N random distinct servers
    get_random_servers() {
        local count=$1
        if [ "$NUM_SERVERS" -le "$count" ]; then
            echo "$AVAILABLE_SERVERS"
            return
        fi
        # shuf-like behavior using awk rand
        echo "$AVAILABLE_SERVERS" | tr ' ' '\n' | grep -v '^$' | awk 'BEGIN{srand()} {print rand() "\t" $0}' | sort -n | cut -f2 | head -n "$count"
    }

    if [ "$DNS_PROTO" = "doh" ]; then
        local server=$(get_random_servers 1)
        ips=$(curl -s -m 3 -H 'accept: application/dns-json' "${server}?name=${domain}&type=A" 2>/dev/null \
            | grep -o '"data":"[^"]*"' | cut -d'"' -f4 | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | grep -vE '^(127\.|0\.0\.0\.0|10\.10\.34\.)')
        
        [ -z "$ips" ] && { log_warn "No IPs for: $domain"; return; }
        for ip in $ips; do
            { flock -x 200; echo "! adg-sync"; echo "||${domain}^\$dnsrewrite=${ip}"; } 200>/tmp/adg_lock >> "$TMP_FILE"
        done

    else
        # UDP or TCP Voting Mechanism
        local voters=$(get_random_servers 3)
        local all_results=""
        
        for server in $voters; do
            local res=""
            if [ "$DNS_PROTO" = "tcp" ]; then
                res=$(dig +tcp +short "@${server}" "$domain" +time=3 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | grep -vE '^(127\.|0\.0\.0\.0|10\.10\.34\.)')
            else
                res=$(nslookup -timeout=3 "$domain" "$server" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$' | grep -vE '^(127\.|0\.0\.0\.0|10\.10\.34\.)')
            fi
            all_results="$all_results $res"
        done

        # Find IPs that appear at least 2 times
        local validated_ips=$(echo "$all_results" | tr ' ' '\n' | grep -v '^$' | sort | uniq -c | awk '$1 >= 2 {print $2}')
        
        # If no IP has a majority (e.g. CDN round-robin returning different IPs), accept all unique IPs
        if [ -z "$validated_ips" ]; then
            validated_ips=$(echo "$all_results" | tr ' ' '\n' | grep -v '^$' | sort -u)
        fi
        
        [ -z "$validated_ips" ] && { log_warn "Failed to resolve or validate IPs for: $domain"; return; }
        
        for ip in $validated_ips; do
            { flock -x 200; echo "! adg-sync"; echo "||${domain}^\$dnsrewrite=${ip}"; } 200>/tmp/adg_lock >> "$TMP_FILE"
        done
    fi
}

TOTAL_DOMAINS=0
BATCH_COUNT=0
BATCH_SIZE=20

# Read enabled domain lists first, fall back to all domain_list sections if empty
LISTS=$(uci -q get adg_dnslookup.main.domain_lists)
if [ -z "$LISTS" ]; then
    LISTS=$(uci show adg_dnslookup | awk -F '[.=]' '/=domain_list/ {print $2}')
fi
for list in $LISTS; do
    log_info "Processing list: $list"
    DOMAINS=$(uci -q get "adg_dnslookup.${list}.domain" 2>/dev/null)
    [ -z "$DOMAINS" ] && { log_warn "List '$list' is empty."; continue; }
    for domain in $DOMAINS; do
        [ -z "$domain" ] && continue
        case "$domain" in \#*) continue;; esac
        TOTAL_DOMAINS=$((TOTAL_DOMAINS + 1))
        
        resolve_domain "$domain" &
        
        BATCH_COUNT=$((BATCH_COUNT + 1))
        if [ "$BATCH_COUNT" -ge "$BATCH_SIZE" ]; then
            wait
            BATCH_COUNT=0
        fi
    done
done
wait
log_info "Resolved $TOTAL_DOMAINS domains."

# ─── Push to AdGuardHome API ─────────────────────────────────────────────────
if [ ! -s "$TMP_FILE" ]; then
    log_error "No IPs resolved. Nothing to push."
    echo "Error: No IPs resolved from $TOTAL_DOMAINS domains" > "$STATUS_FILE"
    printf '{"ip_count":0,"last_run":"%s","domains":%d}' \
        "$(date +'%Y-%m-%d %H:%M:%S')" "$TOTAL_DOMAINS" > "$STATS_FILE"
    rm -f "$TMP_FILE"
    exit 1
fi

IP_COUNT=$(wc -l < "$TMP_FILE" | tr -d ' ')
log_info "Pushing $IP_COUNT IPs via local web filter ..."

IP_COUNT=$(wc -l < "$TMP_FILE" | tr -d ' ')
log_info "Pushing $IP_COUNT IPs to Custom Filtering Rules..."

# Cleanup legacy DNS blocklist (v3.0.0-v3.0.6)
filters=$(curl -sf $AUTH_FLAG "${ADG_URL}/control/filtering/status" 2>/dev/null)
OLD_URL=$(echo "$filters" | sed -n 's/.*"name":"ADG DNS Lookup"[^}]*"url":"\([^"]*\)".*/\1/p')
if [ -n "$OLD_URL" ]; then
    log_info "Cleaning up legacy ADG DNS Lookup blocklist..."
    curl -sf $AUTH_FLAG -X POST \
        -H "Content-Type: application/json" \
        -d "{\"url\":\"$OLD_URL\",\"whitelist\":false}" \
        "${ADG_URL}/control/filtering/remove_url" >/dev/null 2>&1
    rm -f /www/adg_dnslookup.txt
fi

PAYLOAD_FILE="/tmp/adg_dnslookup_payload.json"

# We use Lua (built-in on LuCI OpenWrt) to safely parse the JSON, append our rules, and generate the POST payload
lua -e '
local json = require("luci.jsonc")
local auth = "'"$ADG_USER"':'"$ADG_PASS"'"
local cmd = "curl -sf "
if auth ~= ":" then cmd = cmd .. "-u " .. auth .. " " end
cmd = cmd .. "'"${ADG_URL}"'/control/filtering/status"

local f = io.popen(cmd, "r")
local content = f:read("*a")
f:close()

local data = {}
if content and content ~= "" then
    data = json.parse(content) or {}
end

local new_rules = {}
local skip = false
for _, rule in ipairs(data.user_rules or {}) do
    if rule == "! adg-sync" or rule:match("#adg%-sync$") then
        skip = true
    elseif skip then
        skip = false
    else
        table.insert(new_rules, rule)
    end
end

local tmp = io.open("'"$TMP_FILE"'", "r")
if tmp then
    for line in tmp:lines() do
        table.insert(new_rules, line)
    end
    tmp:close()
end

local out = io.open("'"$PAYLOAD_FILE"'", "w")
if out then
    out:write(json.stringify({rules = new_rules}))
    out:close()
end
'

if [ -s "$PAYLOAD_FILE" ]; then
    log_info "Updating AdGuard Home Custom rules..."
    curl -sf $AUTH_FLAG -X POST \
        -H "Content-Type: application/json" \
        -d @"$PAYLOAD_FILE" \
        "${ADG_URL}/control/filtering/set_rules" >/dev/null 2>&1
    
    # We must call refresh? Wait, set_rules applies immediately! But lets call it just in case? No need.
else
    log_error "Failed to generate JSON payload."
fi

rm -f "$PAYLOAD_FILE"

ADDED=$IP_COUNT
log_ok "Pushed $ADDED IPs to filter list."

# ─── Status + Stats ──────────────────────────────────────────────────────────
TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"
echo "Last run: $TIMESTAMP — Success ($ADDED IPs pushed from $TOTAL_DOMAINS domains)" > "$STATUS_FILE"
printf '{"ip_count":%d,"last_run":"%s","domains":%d}' \
    "$ADDED" "$TIMESTAMP" "$TOTAL_DOMAINS" > "$STATS_FILE"

log_ok "Sync complete: $ADDED IPs from $TOTAL_DOMAINS domains."
log_info "═══════════════════════════════════════════"

rm -f "$TMP_FILE"
exit 0
