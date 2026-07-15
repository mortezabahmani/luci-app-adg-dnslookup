#!/bin/sh
# AdGuard Home DNS Lookup — Sync Engine
# Reads domain lists from UCI, resolves IPs in parallel,
# and injects them into AdGuardHome.yaml using safe awk markers.

LOG_FILE="/var/log/adg_dnslookup.log"
STATUS_FILE="/var/run/adg_dnslookup.status"
STATS_FILE="/var/run/adg_dnslookup.stats"
TMP_FILE="/tmp/adg_dnslookup_ips.tmp"
PID_FILE="/var/run/adg_dnslookup.pid"

# ─── Logging ──────────────────────────────────────────────────────────────────
log() {
    local level="$1"
    local msg="$2"
    local line="$(date +'%Y-%m-%d %H:%M:%S') [$level] $msg"
    echo "$line" >> "$LOG_FILE"

    # Rotate log: keep last 500 lines if over 600
    local lc
    lc=$(wc -l < "$LOG_FILE" 2>/dev/null || echo 0)
    if [ "$lc" -gt 600 ]; then
        tail -n 500 "$LOG_FILE" > "${LOG_FILE}.tmp"
        mv "${LOG_FILE}.tmp" "$LOG_FILE"
    fi
}

log_info()  { log "INFO"  "$1"; }
log_warn()  { log "WARN"  "$1"; }
log_error() { log "ERROR" "$1"; }
log_ok()    { log "OK"    "$1"; }

# ─── Guard: only one instance ─────────────────────────────────────────────────
if [ -f "$PID_FILE" ]; then
    old_pid=$(cat "$PID_FILE")
    if kill -0 "$old_pid" 2>/dev/null; then
        log_warn "Another instance (PID $old_pid) is already running. Exiting."
        exit 0
    fi
fi
echo $$ > "$PID_FILE"
trap 'rm -f "$PID_FILE"' EXIT

log_info "═══════════════════════════════════════════"
log_info "Starting DNS synchronization (PID $$)"

# ─── UCI helpers ──────────────────────────────────────────────────────────────
uci_get() {
    uci -q get "adg_dnslookup.main.$1"
}

# ─── Config ───────────────────────────────────────────────────────────────────
ENABLED=$(uci_get enabled)
if [ "$ENABLED" != "1" ]; then
    log_warn "Service is disabled in UCI. Exiting."
    echo "Disabled" > "$STATUS_FILE"
    exit 0
fi

ADG_CONF=$(uci_get adg_config_path)

# If path is empty, or the file doesn't exist, try to auto-detect
if [ -z "$ADG_CONF" ] || [ ! -f "$ADG_CONF" ]; then
    found=""
    for path in "/etc/adguardhome/adguardhome.yaml" "/etc/adguardhome.yaml" "/etc/AdGuardHome.yaml" "/var/adguardhome/adguardhome.yaml" "/opt/AdGuardHome/AdGuardHome.yaml"; do
        if [ -f "$path" ]; then
            ADG_CONF="$path"
            found="1"
            break
        fi
    done
    
    # If still not found, try a broad find
    if [ -z "$found" ]; then
        path=$(find /etc /var /opt /root /mnt -maxdepth 4 -type f -name '*dGuardHome.yaml' -o -name '*dguardhome.yaml' 2>/dev/null | head -n 1)
        if [ -n "$path" ] && [ -f "$path" ]; then
            ADG_CONF="$path"
            found="1"
        fi
    fi

    # If still not found, keep what we had so the error below logs it
    if [ -z "$found" ] && [ -z "$ADG_CONF" ]; then
        ADG_CONF="/etc/adguardhome.yaml"
    fi
fi

DNS_SERVER=$(uci_get custom_dns)
[ -z "$DNS_SERVER" ] && DNS_SERVER="127.0.0.1"

DNS_PROTO=$(uci_get dns_protocol)
[ -z "$DNS_PROTO" ] && DNS_PROTO="udp"

if [ ! -f "$ADG_CONF" ]; then
    log_error "AdGuardHome config not found at '$ADG_CONF'"
    echo "Error: Config not found at $ADG_CONF" > "$STATUS_FILE"
    exit 1
fi

log_info "Config: $ADG_CONF"
log_info "DNS Server: $DNS_SERVER ($DNS_PROTO)"

# ─── Domain resolution ────────────────────────────────────────────────────────
> "$TMP_FILE"

resolve_domain() {
    local domain="$1"
    local ips=""

    if [ "$DNS_PROTO" = "doh" ]; then
        if ! command -v curl >/dev/null 2>&1; then
            log_error "curl is required for DoH but not installed. Skipping $domain"
            return
        fi
        ips=$(curl -s -H 'accept: application/dns-json' "$DNS_SERVER?name=$domain&type=A" 2>/dev/null \
            | grep -o '"data":"[^"]*"' | cut -d'"' -f4 | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
    elif [ "$DNS_PROTO" = "tcp" ]; then
        if ! command -v dig >/dev/null 2>&1; then
            log_error "bind-dig is required for TCP DNS but not installed. Skipping $domain"
            return
        fi
        ips=$(dig +tcp +short "@$DNS_SERVER" "$domain" 2>/dev/null \
            | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
    else
        # Default UDP via nslookup
        ips=$(nslookup "$domain" "$DNS_SERVER" 2>/dev/null \
            | awk '/^Address: / { print $2 }' \
            | grep -E '^([0-9]{1,3}\.){3}[0-9]{1,3}$')
    fi

    if [ -z "$ips" ]; then
        log_warn "No IPs found for: $domain"
        return
    fi

    for ip in $ips; do
        # Atomic append using a lock — safer than raw >>
        {
            flock -x 200
            printf '  - domain: %s\n    answer: %s\n' "$domain" "$ip" >> "$TMP_FILE"
        } 200>/tmp/adg_lock
    done
}

TOTAL_DOMAINS=0

LISTS=$(uci -q get adg_dnslookup.main.domain_lists 2>/dev/null)
for list in $LISTS; do
    log_info "Processing list: $list"
    # Read all domains in this UCI section
    DOMAINS=$(uci -q get "adg_dnslookup.${list}.domain" 2>/dev/null)
    if [ -z "$DOMAINS" ]; then
        log_warn "List '$list' has no domains or does not exist."
        continue
    fi
    for domain in $DOMAINS; do
        # Skip blank or comment lines
        [ -z "$domain" ] && continue
        case "$domain" in \#*) continue;; esac
        TOTAL_DOMAINS=$((TOTAL_DOMAINS + 1))
        resolve_domain "$domain" &
    done
done

wait
log_info "Finished resolving $TOTAL_DOMAINS domains."

# ─── Inject into AdGuardHome.yaml ─────────────────────────────────────────────
if [ ! -s "$TMP_FILE" ]; then
    log_error "No IPs found. AdGuardHome config was NOT modified."
    echo "Error: No IPs resolved from $TOTAL_DOMAINS domains" > "$STATUS_FILE"
    printf '{"ip_count":0,"last_run":"%s","domains":%d}' \
        "$(date +'%Y-%m-%d %H:%M:%S')" "$TOTAL_DOMAINS" > "$STATS_FILE"
    rm -f "$TMP_FILE"
    exit 1
fi

IP_COUNT=$(grep -c "answer:" "$TMP_FILE" 2>/dev/null || echo 0)
log_info "Found $IP_COUNT valid IPs. Injecting into $ADG_CONF ..."

# Ensure block markers exist in yaml
if ! grep -q "# BEGIN ADG-DNSLOOKUP" "$ADG_CONF"; then
    # Find 'rewrites:' line and insert markers after it
    if grep -q "^rewrites:" "$ADG_CONF"; then
        sed -i '/^rewrites:/a\  # BEGIN ADG-DNSLOOKUP\n  # END ADG-DNSLOOKUP' "$ADG_CONF"
    else
        # rewrites key doesn't exist — append it
        printf '\nrewrites:\n  # BEGIN ADG-DNSLOOKUP\n  # END ADG-DNSLOOKUP\n' >> "$ADG_CONF"
    fi
fi

# Replace block content using awk
awk -v block="$(cat "$TMP_FILE")" '
    /# BEGIN ADG-DNSLOOKUP/ { print; print block; skip=1; next }
    /# END ADG-DNSLOOKUP/   { skip=0 }
    !skip                   { print }
' "$ADG_CONF" > "${ADG_CONF}.new"

if [ $? -ne 0 ] || [ ! -s "${ADG_CONF}.new" ]; then
    log_error "awk injection failed. Original config preserved."
    rm -f "${ADG_CONF}.new"
    exit 1
fi

mv "${ADG_CONF}.new" "$ADG_CONF"
log_ok "Injected $IP_COUNT IPs into $ADG_CONF"

# Reload AdGuard Home
if /etc/init.d/adguardhome reload >/dev/null 2>&1; then
    log_ok "AdGuard Home reloaded successfully."
else
    log_warn "adguardhome reload returned non-zero (may not be installed)."
fi

# ─── Status + Stats files ─────────────────────────────────────────────────────
TIMESTAMP="$(date +'%Y-%m-%d %H:%M:%S')"
echo "Last run: $TIMESTAMP — Success ($IP_COUNT IPs injected from $TOTAL_DOMAINS domains)" > "$STATUS_FILE"
printf '{"ip_count":%d,"last_run":"%s","domains":%d}' \
    "$IP_COUNT" "$TIMESTAMP" "$TOTAL_DOMAINS" > "$STATS_FILE"

log_ok "Synchronization completed: $IP_COUNT IPs from $TOTAL_DOMAINS domains."
log_info "═══════════════════════════════════════════"

rm -f "$TMP_FILE"
exit 0
