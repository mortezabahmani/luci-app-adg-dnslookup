#!/bin/sh
# AdGuard Home DNS Lookup Sync Script

LOG_FILE="/var/log/adg_dnslookup.log"
STATUS_FILE="/var/run/adg_dnslookup.status"

# Function to write to log
log() {
    local msg="$(date +'%Y-%m-%d %H:%M:%S') - $1"
    echo "$msg" >> "$LOG_FILE"
    
    # Truncate log to last 500 lines if it gets too big
    if [ $(wc -l < "$LOG_FILE") -gt 600 ]; then
        tail -n 500 "$LOG_FILE" > "$LOG_FILE.tmp"
        mv "$LOG_FILE.tmp" "$LOG_FILE"
    fi
}

log "Starting DNS synchronization..."

uci_get() {
    uci -q get "adg_dnslookup.main.$1"
}

ENABLED=$(uci_get enabled)
if [ "$ENABLED" != "1" ]; then
    log "Service is disabled in UCI. Exiting."
    echo "Last run: $(date +'%Y-%m-%d %H:%M:%S') - Skipped (Disabled)" > "$STATUS_FILE"
    exit 0
fi

ADG_CONF=$(uci_get adg_config_path)
[ -z "$ADG_CONF" ] && ADG_CONF="/etc/AdGuardHome.yaml"

DNS_SERVER=$(uci_get custom_dns)
[ -z "$DNS_SERVER" ] && DNS_SERVER="127.0.0.1"

if [ ! -f "$ADG_CONF" ]; then
    log "Error: AdGuardHome config not found at $ADG_CONF"
    echo "Last run: $(date +'%Y-%m-%d %H:%M:%S') - Error (Config not found)" > "$STATUS_FILE"
    exit 1
fi

log "Using DNS Server: $DNS_SERVER"

TMP_FILE="/tmp/adg_dnslookup_ips.txt"
> "$TMP_FILE"

resolve_domain() {
    local domain="$1"
    local ips=$(nslookup "$domain" "$DNS_SERVER" 2>/dev/null | awk '/^Address: / { print $2 }' | grep -E '^[0-9.]+$')
    for ip in $ips; do
        echo "  - domain: $domain" >> "$TMP_FILE"
        echo "    answer: $ip" >> "$TMP_FILE"
    done
}

LISTS=$(uci -q get adg_dnslookup.main.domain_lists)

for list in $LISTS; do
    log "Processing list: ${list}"
    DOMAINS=$(uci -q get "adg_dnslookup.${list}.domain")
    if [ -n "$DOMAINS" ]; then
        for domain in $DOMAINS; do
            [ -z "$domain" ] || [ "${domain#\#}" != "$domain" ] && continue
            resolve_domain "$domain" &
        done
    else
        log "Warning: List ${list} has no domains or does not exist."
    fi
done

wait
log "Finished resolving domains."

if [ -s "$TMP_FILE" ]; then
    IP_COUNT=$(grep -c "answer:" "$TMP_FILE")
    log "Found $IP_COUNT valid IPs. Injecting into $ADG_CONF..."
    
    if ! grep -q "# BEGIN ADG-DNSLOOKUP" "$ADG_CONF"; then
        sed -i '/rewrites:/a \
    # BEGIN ADG-DNSLOOKUP\
    # END ADG-DNSLOOKUP' "$ADG_CONF"
    fi

    awk -v block="$(cat $TMP_FILE)" '
        /# BEGIN ADG-DNSLOOKUP/ {
            print
            print block
            skip=1
            next
        }
        /# END ADG-DNSLOOKUP/ {
            skip=0
        }
        !skip { print }
    ' "$ADG_CONF" > "${ADG_CONF}.new"

    mv "${ADG_CONF}.new" "$ADG_CONF"
    log "Reloading AdGuard Home..."
    /etc/init.d/adguardhome reload
    
    log "Synchronization completed successfully."
    echo "Last run: $(date +'%Y-%m-%d %H:%M:%S') - Success ($IP_COUNT IPs injected)" > "$STATUS_FILE"
else
    log "Error: No IPs found. AdGuardHome config was not changed."
    echo "Last run: $(date +'%Y-%m-%d %H:%M:%S') - Error (No IPs found)" > "$STATUS_FILE"
fi

rm -f "$TMP_FILE"
exit 0
