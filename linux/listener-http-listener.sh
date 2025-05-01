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
    PACKAGES="curl"
    RETRY="-o Acquire::Retries=10"
elif command -v yum &>/dev/null; then
    export PACKAGE_MANAGER="yum"
    PACKAGES="curl"
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
mkdir -p /tmp/www/
echo "index" > /tmp/www/index.html
mkdir -p /tmp/www/upload/v2
echo "upload" > /tmp/www/upload/v2/index.html
START_HASH=$(sha256sum --text /tmp/payload_$SCRIPTNAME | awk '{ print $1 }')
while true; do
    log "listener: listen_ip:listen_port"
    screen -S http -X quit
    screen -wipe
    APPLOG=/tmp/http_$SCRIPTNAME.log
    for i in `seq $((MAXLOG-1)) -1 1`; do mv "$APPLOG."{$i,$((i+1))} 2>/dev/null || true; done
    mv $APPLOG "$APPLOG.1" 2>/dev/null || true
    screen -d -L -Logfile /tmp/http.log -S http -m python3 -c "import base64; exec(base64.b64decode('SXlFdmRYTnlMMkpwYmk5bGJuWWdjSGwwYUc5dU13b0tJQ0FnSUdaeWIyMGdhSFIwY0M1elpYSjJaWElnYVcxd2IzSjBJRUpoYzJWSVZGUlFVbVZ4ZFdWemRFaGhibVJzWlhJc0lFaFVWRkJUWlhKMlpYSUtJQ0FnSUdsdGNHOXlkQ0JzYjJkbmFXNW5DZ29nSUNBZ1kyeGhjM01nVXloQ1lYTmxTRlJVVUZKbGNYVmxjM1JJWVc1a2JHVnlLVG9LSUNBZ0lDQWdJQ0JrWldZZ1gzTmxkRjl5WlhOd2IyNXpaU2h6Wld4bUtUb0tJQ0FnSUNBZ0lDQWdJQ0FnYzJWc1ppNXpaVzVrWDNKbGMzQnZibk5sS0RJd01Da0tJQ0FnSUNBZ0lDQWdJQ0FnYzJWc1ppNXpaVzVrWDJobFlXUmxjaWduUTI5dWRHVnVkQzEwZVhCbEp5d2dKM1JsZUhRdmFIUnRiQ2NwQ2lBZ0lDQWdJQ0FnSUNBZ0lITmxiR1l1Wlc1a1gyaGxZV1JsY25Nb0tRb0tJQ0FnSUNBZ0lDQmtaV1lnWkc5ZlIwVlVLSE5sYkdZcE9nb2dJQ0FnSUNBZ0lDQWdJQ0JzYjJkbmFXNW5MbWx1Wm04b0lrZEZWQ0J5WlhGMVpYTjBMRnh1VUdGMGFEb2dKWE5jYmtobFlXUmxjbk02WEc0bGMxeHVJaXdnYzNSeUtITmxiR1l1Y0dGMGFDa3NJSE4wY2loelpXeG1MbWhsWVdSbGNuTXBLUW9nSUNBZ0lDQWdJQ0FnSUNCelpXeG1MbDl6WlhSZmNtVnpjRzl1YzJVb0tRb2dJQ0FnSUNBZ0lDQWdJQ0J6Wld4bUxuZG1hV3hsTG5keWFYUmxLQ0pIUlZRZ2NtVnhkV1Z6ZENCbWIzSWdlMzBpTG1admNtMWhkQ2h6Wld4bUxuQmhkR2dwTG1WdVkyOWtaU2duZFhSbUxUZ25LU2tLQ2lBZ0lDQWdJQ0FnWkdWbUlHUnZYMUJQVTFRb2MyVnNaaWs2Q2lBZ0lDQWdJQ0FnSUNBZ0lHTnZiblJsYm5SZmJHVnVaM1JvSUQwZ2FXNTBLSE5sYkdZdWFHVmhaR1Z5YzFzblEyOXVkR1Z1ZEMxTVpXNW5kR2duWFNrZ0l5QThMUzB0SUVkbGRITWdkR2hsSUhOcGVtVWdiMllnWkdGMFlRb2dJQ0FnSUNBZ0lDQWdJQ0J3YjNOMFgyUmhkR0VnUFNCelpXeG1MbkptYVd4bExuSmxZV1FvWTI5dWRHVnVkRjlzWlc1bmRHZ3BJQ01nUEMwdExTQkhaWFJ6SUhSb1pTQmtZWFJoSUdsMGMyVnNaZ29nSUNBZ0lDQWdJQ0FnSUNCc2IyZG5hVzVuTG1sdVptOG9JbEJQVTFRZ2NtVnhkV1Z6ZEN4Y2JsQmhkR2c2SUNWelhHNUlaV0ZrWlhKek9seHVKWE5jYmx4dVFtOWtlVHBjYmlWelhHNGlMQW9nSUNBZ0lDQWdJQ0FnSUNBZ0lDQWdJQ0FnSUhOMGNpaHpaV3htTG5CaGRHZ3BMQ0J6ZEhJb2MyVnNaaTVvWldGa1pYSnpLU3dnY0c5emRGOWtZWFJoTG1SbFkyOWtaU2duZFhSbUxUZ25LU2tLSUNBZ0lDQWdJQ0FnSUNBZ2NISnBiblFvY0c5emRGOWtZWFJoS1FvZ0lDQWdJQ0FnSUNBZ0lDQnpaV3htTGw5elpYUmZjbVZ6Y0c5dWMyVW9LUW9nSUNBZ0lDQWdJQ0FnSUNCelpXeG1MbmRtYVd4bExuZHlhWFJsS0NKUVQxTlVJSEpsY1hWbGMzUWdabTl5SUh0OUlpNW1iM0p0WVhRb2MyVnNaaTV3WVhSb0tTNWxibU52WkdVb0ozVjBaaTA0SnlrcENnb2dJQ0FnWkdWbUlISjFiaWh6WlhKMlpYSmZZMnhoYzNNOVNGUlVVRk5sY25abGNpd2dhR0Z1Wkd4bGNsOWpiR0Z6Y3oxVExDQndiM0owUFd4cGMzUmxibDl3YjNKMEtUb0tJQ0FnSUNBZ0lDQnNiMmRuYVc1bkxtSmhjMmxqUTI5dVptbG5LR3hsZG1Wc1BXeHZaMmRwYm1jdVNVNUdUeWtLSUNBZ0lDQWdJQ0J6WlhKMlpYSmZZV1JrY21WemN5QTlJQ2duSnl3Z2NHOXlkQ2tLSUNBZ0lDQWdJQ0JvZEhSd1pDQTlJSE5sY25abGNsOWpiR0Z6Y3loelpYSjJaWEpmWVdSa2NtVnpjeXdnYUdGdVpHeGxjbDlqYkdGemN5a0tJQ0FnSUNBZ0lDQnNiMmRuYVc1bkxtbHVabThvSjFOMFlYSjBhVzVuSUdoMGRIQmtMaTR1WEc0bktRb2dJQ0FnSUNBZ0lIUnllVG9LSUNBZ0lDQWdJQ0FnSUNBZ2FIUjBjR1F1YzJWeWRtVmZabTl5WlhabGNpZ3BDaUFnSUNBZ0lDQWdaWGhqWlhCMElFdGxlV0p2WVhKa1NXNTBaWEp5ZFhCME9nb2dJQ0FnSUNBZ0lDQWdJQ0J3WVhOekNpQWdJQ0FnSUNBZ2FIUjBjR1F1YzJWeWRtVnlYMk5zYjNObEtDa0tJQ0FnSUNBZ0lDQnNiMmRuYVc1bkxtbHVabThvSjFOMGIzQndhVzVuSUdoMGRIQmtMaTR1WEc0bktRb0tJQ0FnSUdsbUlGOWZibUZ0WlY5ZklEMDlJQ2RmWDIxaGFXNWZYeWM2Q2lBZ0lDQWdJQ0FnWm5KdmJTQnplWE1nYVcxd2IzSjBJR0Z5WjNZS0NpQWdJQ0FnSUNBZ2FXWWdiR1Z1S0dGeVozWXBJRDA5SURJNkNpQWdJQ0FnSUNBZ0lDQWdJSEoxYmlod2IzSjBQV2x1ZENoaGNtZDJXekZkS1NrS0lDQWdJQ0FnSUNCbGJITmxPZ29nSUNBZ0lDQWdJQ0FnSUNCeWRXNG9LUT09'))"
    screen -S http -X colon "logfile flush 0^M"
    sleep 30
    log "check app url..."
    while ! curl -sv http://localhost:listen_port | tee -a $LOGFILE; do
        log "failed to connect to app url http://localhost:listen_port - retrying"
        sleep 60
    done
    log 'waiting 30 minutes...';
    sleep 1800
    if ! check_payload_update /tmp/payload_$SCRIPTNAME $START_HASH; then
        log "payload update detected - exiting loop and forcing payload download"
        rm -f /tmp/payload_$SCRIPTNAME
        break
    else
        log "restarting loop..."
    fi
done

log "done next stage payload execution."

log "Done"