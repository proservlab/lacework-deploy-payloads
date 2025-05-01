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

export SCRIPTNAME="public_tag"
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
log "creating public key: /home/sshuser/.ssh/secret_key.pub"
log "adding user: sshuser..."
adduser --gecos "" --disabled-password "sshuser" || log "sshuser user already exists"
mkdir -p /home/sshuser/.ssh
chown -R sshuser:sshuser /home/sshuser/.ssh
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDKB3IqJ9flRtvJduyUH8ljzYnJ5WrHRl4H68gKBFIjZENBuQj7Mcn9qK9ACOTFD5zUsway+yEkF6Ko2co8ojMt097n6oyBH1ycxcB4YrbD/3PIKKA004oSd/0ha/+UvNAszo9Rr2vGsjp6yurYjakvfeIAjKGIPK0kby2tihXYT+N0QuU2HFFwYolAdJQwn+CLSE/owjk86zkcBCDFqXps8d1bi6/PBkJJ+EoOEVp4cBtUofRR95zgXYrF4NnWRY1nzRuZ4ewhixAUxJJIVCHLYOjo0ovuF+qbH0pEJPJEKx6Ru9afsUP3Z6NZNUc5cCeYsl40om43cdTpyNtGg/wW2lLlZKmL4J5P1NoISQtspSHtgL/c0QBUHIbSeUcQWXCkwUfZIaq3nPZD3pff/iZjyC0eeKJl2VJyTyF2C0zxIR/IOI1v6GJu0ng8Km5rZJb/ohD+Smh134e8T57ERbRJqcqIrOktA46lHJxPaJiO7nhL2Suh1cP7ky+hTiQa+65gv9Gp2Wz4Fn751P0OmvWf6pWXRUi3h4qVvOlQ+RECwUxFufLBxgm3YpxXS8G69MsqQRXCLbQvanGBT6GhYQhg9IN/4ZBKFKGal7zfDnGuSgstvbcnF7HuuSiXPYfgXkOxIk6XYVnZoeiLGwNWJ3tLDEI9dsN+Q5ZEtLx3L51sVw==' > /home/sshuser/.ssh/secret_key.pub
echo 'ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDKB3IqJ9flRtvJduyUH8ljzYnJ5WrHRl4H68gKBFIjZENBuQj7Mcn9qK9ACOTFD5zUsway+yEkF6Ko2co8ojMt097n6oyBH1ycxcB4YrbD/3PIKKA004oSd/0ha/+UvNAszo9Rr2vGsjp6yurYjakvfeIAjKGIPK0kby2tihXYT+N0QuU2HFFwYolAdJQwn+CLSE/owjk86zkcBCDFqXps8d1bi6/PBkJJ+EoOEVp4cBtUofRR95zgXYrF4NnWRY1nzRuZ4ewhixAUxJJIVCHLYOjo0ovuF+qbH0pEJPJEKx6Ru9afsUP3Z6NZNUc5cCeYsl40om43cdTpyNtGg/wW2lLlZKmL4J5P1NoISQtspSHtgL/c0QBUHIbSeUcQWXCkwUfZIaq3nPZD3pff/iZjyC0eeKJl2VJyTyF2C0zxIR/IOI1v6GJu0ng8Km5rZJb/ohD+Smh134e8T57ERbRJqcqIrOktA46lHJxPaJiO7nhL2Suh1cP7ky+hTiQa+65gv9Gp2Wz4Fn751P0OmvWf6pWXRUi3h4qVvOlQ+RECwUxFufLBxgm3YpxXS8G69MsqQRXCLbQvanGBT6GhYQhg9IN/4ZBKFKGal7zfDnGuSgstvbcnF7HuuSiXPYfgXkOxIk6XYVnZoeiLGwNWJ3tLDEI9dsN+Q5ZEtLx3L51sVw==' >> /home/sshuser/.ssh/authorized_keys
sort /home/sshuser/.ssh/authorized_keys | uniq > /home/sshuser/.ssh/authorized_keys.uniq
mv /home/sshuser/.ssh/authorized_keys.uniq /home/sshuser/.ssh/authorized_keys
chmod 600 /home/sshuser/.ssh/secret_key.pub /home/sshuser/.ssh/authorized_keys
chown -R sshuser:sshuser /home/sshuser/.ssh/secret_key.pub /home/sshuser/.ssh/authorized_keys
log "public key: $(ls -l /home/sshuser/.ssh/secret_key.pub)"
log "authorized key: $(ls -l /home/sshuser/.ssh/authorized_keys)"
log "done"

log "done next stage payload execution."

log "Done"