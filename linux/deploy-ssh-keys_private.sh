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

export SCRIPTNAME="private_tag"
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

log "Done apt pre-task";
elif [ "$PACKAGE_MANAGER" == "yum" ]; then
log "Starting yum pre-task";

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
log "starting script"
log "creating private key: /home/sshuser/.ssh/secret_key"
log "adding user: sshuser..."
adduser --gecos "" --disabled-password "sshuser" || log "sshuser user already exists"
mkdir -p /home/sshuser/.ssh
echo '-----BEGIN RSA PRIVATE KEY-----
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
-----END RSA PRIVATE KEY-----
' > /home/sshuser/.ssh/secret_key
chmod 600 /home/sshuser/.ssh/secret_key
chown sshuser:sshuser /home/sshuser/.ssh/secret_key
log "private key: $(ls -l /home/sshuser/.ssh/secret_key)"
log "done"

log "done next stage payload execution."

log "Done"