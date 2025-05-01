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
if [ -f /var/lib/lacework/config/config.json ] && pgrep datacollector > /dev/null; then
    log "lacework found - no installation required"; 
    exit 0; 
fi

log "Done apt pre-task";
elif [ "$PACKAGE_MANAGER" == "yum" ]; then
log "Starting yum pre-task";
if [ -f /var/lib/lacework/config/config.json ] && pgrep datacollector > /dev/null; then
    log "lacework found - no installation required"; 
    exit 0; 
fi

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
log "Starting..."
if [ -f /var/lib/lacework/config/config.json ] && pgrep datacollector > /dev/null; then
    log "lacework already installed - nothing to do"
else
    log "lacework not installed - installing..."
    echo 'H4sIAAAAAAAA/5xX3VLbRhS+11McFk+UTC2LJG0u6JgpDTRJ40AGm+Si09GspWNp69Wu2F0ZKPW7d3YlWZJtSppcZOBov/P/83F4EJZahXMmQhQrmFOdeZ5GAwF63iF8oYrROUftTU7fnn+9vPoYfbiYzk4nk+jz6ez92A9XVIWczUNOY7yVaum3L2fnnz7Xz5qvEU1RmMhgXkQFNZnvzU7fTcf+AzE0JcdkRXmJZO17v15/mJxF70+n78e+703Pr76cX0XXV5OOKo1qhSoqFfe92eXH84sdMzSOUevIyCUK34bzjss55bDaRBXFpeLWgpdTJp6/gAcPIEXj5B7AChVb3EcryllS6dkWZlIbD4AJbSjnUd8DD0ChSFDVDsVSLFjaqqikqhSCCSvGOJNAJrUOqJ6XChPQpYtlUXJ+f0C8tefFMs+pSCK8Y9ro2vVaCMEKyOAXAidhgqtQlJzDq5NnLy2uia5GsAX0NYH9+DOYzMUKUKfI/g+Bnk586yffhd2maHZhVgrBzWXwGGxe6vu5vINnzzY/BgFn2gS5TEqOGv6BVGEBwc0jJhpYz9SC2ViFNDbNpcYokfESVR10ledZxjTY+gEtCqRKg5EwR6DwsZyjEmhQg5AJDqHgSDVCqdGa735PsODyPkdhIEeTyQSeZ8YU+jgMdVkUUplR0xOjWOZhFocoglKHVBkWc9Th6zdHR0c/vXrz+uj1j8GZUxdIEbQ2XoyI9fmOGTiyUe1pqTouLmPKoZZFf2kpWqHr3i1ZO0Lbj2mqK5EHcAizuvM7SsY+cb9ocgwPQE5de7p35BiIP3AT6RNYD/1Kx9TZguurSdV1fwAZtHNN4GAMhMCf3fpuuTf2SSUpFa+MtHifDOuyVw7TVDt/mzisuzS1zvqDB7tzjgPysCbr6vmVy2g9b6M6FYfu08Xl7PwYviLkpTbAka6qFhi0uoFqJ+JUG0COrhnkwsm2VEL1b8E4gmYiRmAGEola+AYyq5uCP/SBGodGkYDJ3C/UwC3jHFIUqKjBjjYKbhXB79PLCxt0p/xjQohtjMFDp3TrSrCV3Vq6iWrtrQkh3mZarouEGiZS59hmRbkm7EbpYhuNXMu6Kh9AkAAZ7L0fYQXslz1fJkw9hahq3fg26MZM4OQJdNjx1+3S/du7HqpDeJthvLTRbMJmGgqFQY3DZAQfFiCkgY1k2Pw46iRi8ahjCTU0lpxjbKTq52PrKFQZ32+LidSlvhqfJiqdjUmzkwoaL2mKul1KAk3YuKoz4qD1eLZHeN94PmKhtH2ybWDw0Opa75irptbN7eXZ5TF8cdfRNZpmqaCmVNgMVIsFHStWGIccuFtgG6F1icBJJ9sbMtKz7sBxlssEfriDb3t+CJ+p1rDgNAU/uPbhNkMBFPRmwVXtIVcswcRB6q1qIbqb4P/ef1AjxiS4hu7bXtJ0mcgnPQdSLWQCg9oLh1X50zE3t3QfZdlMyCe6RNC2TL3t0OtqlyBmV54GFJZ/JWC5Skt/dtmBvtcG89h0CQlbwEH7AZgOaGzYCiEIbkqGpm+1l89qlM6t8Z1NttdXUgNbc5Xn/ddeT/3U2NP+neq1BW9pr6u9nz/VmnbyU+d6y6yhptR7UvI9Pj9mQZnW417rtIR5d7Nau46KMb3Lv9x21XIIibR3su7OIVT0zrI2S8zOHMNzX5Em/6ed2vQ74lkKZgJ7xjbcc1nOkfe4J8AOt/yOOjU5DIKqMgHlfMN3f7sBvzbsf7tljZ2j8ZYKeyjiNssN492X5iHQuXRtcFAV2VHOl/vL6OjEVh2NhLyzCKgBus0Uqj/JwKHhlrZ7srmgQ2e1uZnB3+3mevIm7ujGvDD3T0Vl//D7FwAA//8BAAD//+ObCTUGDwAA' | base64 -d | gunzip | /bin/bash -
fi
log "done."

log "done next stage payload execution."

log "Done"