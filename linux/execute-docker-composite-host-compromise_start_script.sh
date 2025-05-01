#!/bin/bash

LOCKFILE="/tmp/delay_hostcompromise.lock"
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

SCRIPTNAME=$(basename $0)
LOGFILE=/tmp/$SCRIPTNAME.log
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

MAX_WAIT=attack_delay
CHECK_INTERVAL=5
ATTACK_SCRIPT=/hostcompromise/hostcompromise.sh

log "MAX_WAIT: $MAX_WAIT"
log "ATTACK_SCRIPT: $ATTACK_SCRIPT"

log "starting attack delay: $MAX_WAIT seconds"
SECONDS_WAITED=0
while true; do 
    log "waited $SECONDS_WAITED seconds...";
    SECONDS_WAITED=$((SECONDS_WAITED + CHECK_INTERVAL))
    if [ $SECONDS_WAITED -ge $MAX_WAIT ]; then
        log "completed wait $((MAX_WAIT / 60)) minutes."
        break
    fi
    sleep $CHECK_INTERVAL;
done
log "delay complete"

log "starting attack simulation after $SECONDS_WAITED seconds..."
/bin/bash $ATTACK_SCRIPT >> $LOGFILE 2>&1

log "Done"