#!/bin/bash

set -e
LOCKFILE="/tmp/composite.lock"
if [ -e "$LOCKFILE" ]; then
  echo "Another instance of the script is already running. Exiting..."
  exit 1
else
  mkdir -p "$(dirname "$LOCKFILE")" && touch "$LOCKFILE"
fi
function cleanup {
    rm -f "$LOCKFILE"
}
trap cleanup EXIT INT TERM

# set max vpn wait to 5 minutes
MAX_WAIT=300
CHECK_INTERVAL=5

LOGFILE=/tmp/attacker_cloud_cryptomining_auto-paid.sh.log
function log {
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1"
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" >> $LOGFILE
}
MAXLOG=2
for i in `seq $((MAXLOG-1)) -1 1`; do mv "$LOGFILE."{$i,$((i+1))} 2>/dev/null || true; done
mv $LOGFILE "$LOGFILE.1" 2>/dev/null || true
check_apt() {
  pgrep -f "apt" || pgrep -f "dpkg"
}
while check_apt; do
  log "Waiting for apt to be available..."
  sleep 10
done

function wait_vpn_connection {
    SECONDS_WAITED=0
    while ! docker logs protonvpn 2>&1  | grep "Connected!"; do 
        log "waiting for connection...";
        SECONDS_WAITED=$((SECONDS_WAITED + CHECK_INTERVAL))
        if [ $SECONDS_WAITED -ge $MAX_WAIT ]; then
            log "Connection is still not available after waiting for $((MAX_WAIT / 60)) minutes."
            break
        fi
        sleep $CHECK_INTERVAL;
    done
}
function execute_script {
    if [ $SECONDS_WAITED -lt $MAX_WAIT ]; then
        log "Starting docker log for $1..."
        docker logs protonvpn -f > /tmp/$1.log 2>&1 &
        log "Executing cloudcrypto"
        bash start.sh --container=terraform --env-file=.env-aws-compromised_keys_user --script="cloudcrypto" >> $LOGFILE 2>&1
        log "Done cloudcrypto."
    else
        log "VPN connect timeout - skipping"
    fi;
}

# baseline
log "Start protonvpn with .env-protonvpn-paid-US"
bash start.sh --container=protonvpn --env-file=.env-protonvpn-paid-US >> $LOGFILE 2>&1
wait_vpn_connection
if [ $SECONDS_WAITED -lt $MAX_WAIT ]; then
    log "Starting docker log for protonvpn-US..."
    docker logs protonvpn -f > /tmp/protonvpn-US.log 2>&1 &
    log "Executing baseline.sh"
    bash start.sh --container=aws-cli --env-file=.env-aws-compromised_keys_user --script="baseline.sh" >> $LOGFILE 2>&1
    log "Done baseline."
else
    log "VPN connect timeout - skipping"
fi;

log "Wait attack_delay seconds before starting attacker cloudcrypto..."
sleep attack_delay

SERVERS="AU JP NL SG LV CR IS"
for SERVER in $SERVERS; do
    log "Wait 60 seconds before starting attacker cloudcrypto..."
    sleep 60
    log "Start protonvpn with .env-protonvpn-paid-$SERVER"
    bash start.sh --container=protonvpn --env-file=.env-protonvpn-paid-$SERVER >> $LOGFILE 2>&1
    wait_vpn_connection
    execute_script "protonvpn-$SERVER"
done

log "Attack simulation complete."