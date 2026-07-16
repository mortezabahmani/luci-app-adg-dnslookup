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
            | grep -o '"data":"[^"]*"' | cut -d'"' -f4 | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
        
        [ -z "$ips" ] && { log_warn "No IPs for: $domain"; return; }
        for ip in $ips; do
            { flock -x 200; echo "||${domain}^\$dnsrewrite=${ip}" >> "$TMP_FILE"; } 200>/tmp/adg_lock
        done

    else
        # UDP or TCP Voting Mechanism
        local voters=$(get_random_servers 3)
        local all_results=""
        
        for server in $voters; do
            local res=""
            if [ "$DNS_PROTO" = "tcp" ]; then
                res=$(dig +tcp +short "@${server}" "$domain" +time=3 2>/dev/null | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
            else
                res=$(nslookup -timeout=3 "$domain" "$server" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
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
            { flock -x 200; echo "||${domain}^\$dnsrewrite=${ip}" >> "$TMP_FILE"; } 200>/tmp/adg_lock
        done
    fi
}

TOTAL_DOMAINS=0
BATCH_COUNT=0
BATCH_SIZE=20

# Get all lists by reading domain_list sections (bypasses main.domain_lists sync issues)
LISTS=$(uci show adg_dnslookup | awk -F '[.=]' '/=domain_list/ {print $2}')
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

# Move the temporary file to the web directory for uhttpd serving
FILTER_FILE="/www/adg_dnslookup.txt"

# Extract actual OpenWrt LAN IP (strip CIDR subnet mask if present) to ensure correct routing
ROUTER_HOST=$(uci -q get network.lan.ipaddr | cut -d/ -f1)
[ -z "$ROUTER_HOST" ] && ROUTER_HOST=$(echo "$ADG_URL" | awk -F/ '{print $3}' | cut -d: -f1)
[ -z "$ROUTER_HOST" ] && ROUTER_HOST="127.0.0.1"
FILTER_URL="http://${ROUTER_HOST}/adg_dnslookup.txt"
FILTER_NAME="ADG DNS Lookup"

mv "$TMP_FILE" "$FILTER_FILE"
chmod 644 "$FILTER_FILE"

# Add the filter list in AdGuard Home if not exists, and cleanup old instances
log_info "Updating AdGuard Home filter lists..."
filters=$(curl -sf $AUTH_FLAG "${ADG_URL}/control/filtering/status" 2>/dev/null)

# Find if a list named "ADG DNS Lookup" exists but has an old URL
OLD_URL=$(echo "$filters" | sed -n 's/.*"url":"\([^"]*\)"[^}]*"name":"'"$FILTER_NAME"'".*/\1/p')
[ -z "$OLD_URL" ] && OLD_URL=$(echo "$filters" | sed -n 's/.*"name":"'"$FILTER_NAME"'"[^}]*"url":"\([^"]*\)".*/\1/p')

if [ -n "$OLD_URL" ] && [ "$OLD_URL" != "$FILTER_URL" ]; then
    log_info "Removing outdated filter URL: $OLD_URL"
    curl -sf $AUTH_FLAG -X POST \
        -H "Content-Type: application/json" \
        -d "{\"url\":\"$OLD_URL\",\"whitelist\":false}" \
        "${ADG_URL}/control/filtering/remove_url" >/dev/null 2>&1
fi

if ! echo "$filters" | grep -q "\"url\":\"$FILTER_URL\""; then
    log_info "Registering custom filter list at $FILTER_URL..."
    curl -sf $AUTH_FLAG -X POST \
        -H "Content-Type: application/json" \
        -d "{\"name\":\"$FILTER_NAME\",\"url\":\"$FILTER_URL\",\"whitelist\":false}" \
        "${ADG_URL}/control/filtering/add_url" >/dev/null 2>&1
fi

log_info "Refreshing filters..."
curl -sf $AUTH_FLAG -X POST \
    -H "Content-Type: application/json" \
    -d "{\"whitelist\":false}" \
    "${ADG_URL}/control/filtering/refresh" >/dev/null 2>&1

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
