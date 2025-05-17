#!/bin/bash

export LOGFILE="/tmp/lacework_deploy_$TAG.log"

if [ -z $MAXLOG ]; then
    MAXLOG=2
fi

log() {
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1"
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" >> $LOGFILE
}

lockfile() {
    if command -v yum && ! command -v ps; then
        RETRY="--setopt=retries=10"
        yum update $RETRY -y && yum $RETRY install -y procps
    fi

    LOCKFILE="/tmp/payload_$TAG.lock"
    CURRENT_PROCESS=$(echo $$)
    PROCESSES=$(pgrep -f "\| tee /tmp/payload_$TAG \| base64 -d \| gunzip")
    PROCESS_NAMES=$(echo -n $TAG | xargs --no-run-if-empty ps fp)
    COUNT=$(pgrep -f "\| tee /tmp/payload_$TAG \| base64 -d \| gunzip" | wc -l)
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
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

random_sleep() {
    local MAX_WAIT=$1
    local RAND_WAIT=$(($RANDOM%($MAX_WAIT-30+1)+30))
    log "waiting $RAND_WAIT seconds before starting..."
    sleep $RAND_WAIT
}

get_base64gzip() {
  local payload="$1"
  echo $payload | base64 -d | gunzip
}

cleanup() {
    rm -f "$LOCKFILE"
}

rotate_log() {
    local MAXLOG=$1
    # Log rotate
    for i in `seq $((MAXLOG-1)) -1 1`; do mv "$LOGFILE."{$i,$((i+1))} 2>/dev/null || true; done
    mv $LOGFILE "$LOGFILE.1" 2>/dev/null || true
}

# Wait for Package Manager
wait_for_package_manager() {
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

main_loop() {
    START_HASH=$(sha256sum --text /tmp/payload_$SCRIPTNAME | awk '{ print $1 }')
    while true; do
        
        # run the payload
        if (( $# == 0 )) ; then
            $(base64 --decode < /dev/stdin) | /bin/bash -
        else
            echo $1 | base64 -d | /bin/bash -
        fi

        # once complete check if the payload has changed and exit loop if it has
        if ! check_payload_update /tmp/payload_$SCRIPTNAME $START_HASH; then
            log "payload update detected - exiting loop and forcing payload download"
            rm -f /tmp/payload_$SCRIPTNAME
            break
        else
            log "restarting loop..."
        fi
    done
}

preinstall_cmd() {
    local preinstall_cmd_base64=$1
    # Conditional Commands based on package manager
    if [ "$PACKAGE_MANAGER" == "apt-get" ]; then
        log "Starting apt pre-task";
        echo $preinstall_cmd_base64 | base64 -d | /bin/bash -
        log "Done apt pre-task";
    elif [ "$PACKAGE_MANAGER" == "yum" ]; then
        log "Starting yum pre-task";
        echo $preinstall_cmd_base64 | base64 -d | /bin/bash -
        log "Done yum pre-task";
    fi
}

install_packages() {
    local packages=$1
    if [ "" != "$packages" ]; then
        while true; do
            /bin/bash -c "$PACKAGE_MANAGER update && $PACKAGE_MANAGER install -y $packages" >> $LOGFILE 2>&1
            if [ $? -ne 0 ]; then
                log "Failed to install some_package using $PACKAGE_MANAGER - retry required"
                while ! wait_for_package_manager; do
                    RAND_WAIT=$(($RANDOM%(300-30+1)+30))
                    log "Waiting for $PACKAGE_MANAGER to be available - sleeping $RAND_WAIT"
                    sleep $RAND_WAIT
                done
            else
                break
            fi
        done
    fi
}

postinstall_cmd() {
    local postinstall_cmd_base64=$1
    # Conditional Commands based on package manager
    if [ "$PACKAGE_MANAGER" == "apt-get" ]; then
        log "Starting apt pre-task";
        echo $postinstall_cmd_base64 | base64 -d | /bin/bash -
        log "Done apt pre-task";
    elif [ "$PACKAGE_MANAGER" == "yum" ]; then
        log "Starting yum pre-task";
        echo $postinstall_cmd_base64 | base64 -d | /bin/bash -
        log "Done yum pre-task";
    fi
}

# Determine Package Manager
if command_exists "apt-get"; then
    export PACKAGE_MANAGER="apt-get"
    export RETRY="-o Acquire::Retries=10"
elif command_exists "yum"; then
    export PACKAGE_MANAGER="yum"
    export RETRY="--setopt=retries=10"
fi

trap cleanup EXIT INT TERM
trap cleanup SIGINT

install_packages "jq curl procps"

rotate_log $MAXLOG
lockfile

export -f get_base64gzip random_sleep command_exists rotate_log cleanup lockfile log check_payload_update wait_for_package_manager