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

DNS_SERVER=$(uci_get custom_dns)
[ -z "$DNS_SERVER" ] && DNS_SERVER="127.0.0.1"

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
log_info "DNS: $DNS_SERVER ($DNS_PROTO)"

# ─── Domain resolution ────────────────────────────────────────────────────────
> "$TMP_FILE"

resolve_domain() {
    local domain="$1" ips=""

    case "$DNS_PROTO" in
        doh)
            command -v curl >/dev/null 2>&1 || { log_error "curl required for DoH. Skipping $domain"; return; }
            ips=$(curl -s -H 'accept: application/dns-json' "${DNS_SERVER}?name=${domain}&type=A" 2>/dev/null \
                | grep -o '"data":"[^"]*"' | cut -d'"' -f4 | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
            ;;
        tcp)
            command -v dig >/dev/null 2>&1 || { log_error "bind-dig required for TCP. Skipping $domain"; return; }
            ips=$(dig +tcp +short "@${DNS_SERVER}" "$domain" 2>/dev/null \
                | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
            ;;
        *)
            ips=$(nslookup "$domain" "$DNS_SERVER" 2>/dev/null \
                | awk '/^Address: / { print $2 }' \
                | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
            ;;
    esac

    [ -z "$ips" ] && { log_warn "No IPs for: $domain"; return; }

    for ip in $ips; do
        { flock -x 200; echo "${domain} ${ip}" >> "$TMP_FILE"; } 200>/tmp/adg_lock
    done
}

TOTAL_DOMAINS=0
BATCH_COUNT=0
BATCH_SIZE=20

LISTS=$(uci -q get adg_dnslookup.main.domain_lists 2>/dev/null)
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
log_info "Pushing $IP_COUNT rewrites via API ..."

# Get existing rewrites managed by us (we tag with a comment-marker domain)
# Strategy: fetch all rewrites, delete ours (tagged), then add new ones.
# Tag: we prefix nothing — we just track what we added in a local state file.
STATE_FILE="/var/run/adg_dnslookup.state"

# Delete previously added rewrites
if [ -f "$STATE_FILE" ]; then
    log_info "Cleaning previous rewrites ..."
    while IFS=' ' read -r old_domain old_ip; do
        curl -sf $AUTH_FLAG -X POST \
            -H "Content-Type: application/json" \
            -d "{\"domain\":\"${old_domain}\",\"answer\":\"${old_ip}\"}" \
            "${ADG_URL}/control/rewrite/delete" >/dev/null 2>&1
    done < "$STATE_FILE"
    log_ok "Cleaned old rewrites."
fi

# Add new rewrites
ADDED=0
FAILED=0
while IFS=' ' read -r domain ip; do
    if curl -sf $AUTH_FLAG -X POST \
        -H "Content-Type: application/json" \
        -d "{\"domain\":\"${domain}\",\"answer\":\"${ip}\"}" \
        "${ADG_URL}/control/rewrite/add" >/dev/null 2>&1; then
        ADDED=$((ADDED + 1))
    else
        FAILED=$((FAILED + 1))
        log_warn "Failed to add rewrite: $domain -> $ip"
    fi
done < "$TMP_FILE"

# Save state for next cleanup
cp "$TMP_FILE" "$STATE_FILE"

log_ok "Pushed $ADDED rewrites ($FAILED failed)."

# ─── Status + Stats ──────────────────────────────────────────────────────────
TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"
echo "Last run: $TIMESTAMP — Success ($ADDED IPs pushed from $TOTAL_DOMAINS domains)" > "$STATUS_FILE"
printf '{"ip_count":%d,"last_run":"%s","domains":%d}' \
    "$ADDED" "$TIMESTAMP" "$TOTAL_DOMAINS" > "$STATS_FILE"

log_ok "Sync complete: $ADDED IPs from $TOTAL_DOMAINS domains."
log_info "═══════════════════════════════════════════"

rm -f "$TMP_FILE"
exit 0
