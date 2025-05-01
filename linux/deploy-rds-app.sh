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
    PACKAGES="curl python3-pip mysql-client-core-8.0"
    RETRY="-o Acquire::Retries=10"
elif command -v yum &>/dev/null; then
    export PACKAGE_MANAGER="yum"
    PACKAGES="curl python3-pip mysql-shell"
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
screen -S vuln_rdsapp_target -X quit
screen -wipe
truncate -s 0 /tmp/vuln_rdsapp_target.log
log "removing previous app directory"
rm -rf /vuln_rdsapp_target
log "building app directory"
mkdir -p /vuln_rdsapp_target/templates
cd /vuln_rdsapp_target
    
echo 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 | base64 -d | gunzip > app.py
echo H4sIAAAAAAAA/3LLSSzOtrU10jPUM+YCc+IdAzxtbY31DPQK8otLDLkKKnMriwtzbG0N9Qz0jLmS8kvyjUEcI1M9EzAvOb8oFSxgoWfKVVDpX5CaFxzsY2trZKxnrGfAFZ5alF2VWpoOssRIz4gLAAAA//8BAAD//4QmCuxyAAAA | base64 -d | gunzip > requirements.txt
echo H4sIAAAAAAAA/6xVTW8bNxC981cQ6oG7gLyw0x4KAzxI1iY1IMuqJDctBIGiuCOJyC655XDjGkH+e8H9shzUjgpEJ86bj/d2NEPqorTO09weDtocSGuWT8UT/p2TvbNFZyTgHG39E+nlTiKkzlnXJe2stz+fGso6SBAQtTUdbrEp2vsrr3Ps6t4a9NIouAMvM+nle/DqCO6bFOUgA+O1fD1x7uxnnYEjJNfohd0LIwtAyulgQMhPtEKgoN5R3eZRZ3MgZZtF+asFI0IppVoWImSIfSOQvyI88roAW3l+dXl5OaSmKoT0HorSI38XxyR8SRDVESe5lVkUE9J2jfKmq8mysRt2+YhCKgWI4hM8CZ3xuk7yjA37OATlwJ+Et7Et/k1sTSK8/QSmjavPTYiDQ/CGRnKW7URjMxLkYkE5bfMTlWswPmKIBYsJKaWTBfi6rYhFcgAveiyadeWOFj0b0o/aHyeg3FPptTV85SqIyWQsRvO5eFhMQ7O63DWbd0e2WbM/ZF4B2yRY5tpHg+tBvL7chNT5/WJFOdXGR/8j92pzvvbQkze0z0Z36feFn81WIbjvMD4s08WPpi0l4qN12Ru089Fy+fF+MTmH9VzadsxeJ12kH27vZ+dQWkzAfNbOmjWb3o7v/lr+PhXpbDSepuJmmo4Wq/TPlZhPHz7cztiGcsquGCHL5VTcjILlMrxQtthpA9mFkhe7ymQ5JCUUjJBm6v9jDVyGLCaIOeX0C1OSXb9Z6Supd45y2hRIDmDASQ8i2wlZ+WOzn81VMBn/ZtHXK/m8I0M6t87zdvKHdDJ+aCeGn47GkC7q1vK+hzEpXdiSmiAmyhoDyjf3UPcKtGBDH3b2lLgGw3i+JKrhbnz4yZVSnuqskWzH24VpbMScI+aNoY7SIXjOKr//tdj9wlq4cmidyiUi72XWGCYTrfxNfQ73VIOG1vaf1kZGcetM4B9QlYdosEyn6c2KbvfaoQ/juB3SbS6fz0GOVB5cDdD3i/s7ulUS/XYQuCR6EV4fyul6Q/bWUWcfqTat3qR+O2SeR/F18xldQiLLEkzWtDj8vrBeA7sOVdaDHhhshpR1qjpvZ9fOFzK7iBfgYPM13HX1f9+r6NuVqNwiRKfz0EP/AgAA//8BAAD//3CNgsc/CAAA | base64 -d | gunzip > test.py
curl -LOJ https://s3.amazonaws.com/rds-downloads/rds-combined-ca-bundle.pem
echo H4sIAAAAAAAA/5SSUW/aPBSG7/kV5+ZTmiqqvu2Wm7mJAY/EMNsp61XlBo9YOPZknEr8+8khNO06adrdgfO8fp9IJ2cYCQwFEugecQxkAXQjAH8nXHDYPz9Z2an5rOZ4+jFmBLovfw808hTgRu+hwgWpK0LFsKV1WQKqxeaJ0JzhClOR/dD+FKjsFDwglq8Qu/n0+f80M/JP/zat9LIJyn9cbRmpEHuENX6MzWk6nwlW03xSjFLzGaEcMwGEis2o+WqQwbU1g3dNKTygssZ8BgBwk+y0MVp2SQYJb2Wwysfxq+zUCcQdrLU/Jmk2wqVyVvp9JKju3HlI/XTNG6RQC+fVKcTVWhmjBmgMQtXk7jzBQ03cF8610sapcjYcXKf8GXjjQpjgnTThYrd2yupDnLbyRRnIW3V0LxNJddPG6otn0zozlNCzCxLqtvdyYpfK+cNACnlUOg4rfZS+B96bfuKYbqTfu6uiNM8X33UrLVDnrFYWuLaHNklfz6nmmH08v/6k/JfkvwRIgakgC4IL2BGxArTjqA+tskE3Mmhnt6Y/aAuIQ8IKnsxnS4aogJqjJYYNhdu7WxAbSMZHk+FVhr/VhGHgvLwGUFnClpEHUuIl5jE5Hv5f86gUmF2+4z317+6LsuarNxrzXwAAAP//AQAA///9hHkMqAMAAA== | base64 -d | gunzip > bootstrap.sql
echo H4sIAAAAAAAA/1JW1E/KzNNPSizO4OJKrSjILypRcPNxDPaOdwwIsNUvK83Jiy9KKU4sKIgvSSxKTy3RTywo0CuoRFXr4uoU6m5rwJWWk1icrVBUmqegm6FgoAeGCroFCjmZxSWpefEgHQAAAAD//wEAAP//Dq2WI3EAAAA= | base64 -d | gunzip > entrypoint.sh
echo H4sIAAAAAAAA/7JRdPF3DokMcFXIKMnNseOygVJJ+SmVdlylxalFeYm5qVYK1dUKMI5Cba2Ogk2iQkZRapqtEkiiKCc+Lb9IQz0nPz2/tERdU6G2VskOwrHRT7TjstGHGGejDzYdAAAA//8BAAD//+vjW6h0AAAA | base64 -d | gunzip > templates/index.html
echo H4sIAAAAAAAA/4yRvW6EMAyAd57CHVhrsVtZaDuhtsMtNxoSlEj8SMHLCfHup1yCDgkOXRYr9hf7U0wfX3/l5fr/DVb6TmW0BsNaZQAAJE46o0qeBCo3CWFMZIQRonrUt8TaYgvaYm3BdXgB6ZD45yUmrPpxfhL45d4Qit3XKz4tl5Y9N2L8AUO4HTjn0I4emtDPDTHmy5mcVvP84D7bIBkGwLIQin5Ndvwm2Kzih/RO3Qw62CdhwvS1hHELhHGBdwAAAP//AQAA//+k+Kt32AEAAA== | base64 -d | gunzip > templates/cast.html

log "updating entrypoing permissions"
chmod 755 entrypoint.sh

log "installing requirements..."
python3 -m pip install -r requirements.txt >> $LOGFILE 2>&1
log "requirements installed"
    
log "running mysql boostrap..."
mysql --ssl-ca=rds-combined-ca-bundle.pem --ssl-mode=REQUIRED -h db_host -udb_user -pdb_password < bootstrap.sql
log "mysql boostrap complete"

START_HASH=$(sha256sum --text /tmp/payload_$SCRIPTNAME | awk '{ print $1 }')
while true; do
    log "starting app"
    screen -S vuln_rdsapp_target -X quit
    screen -wipe
    screen -d -L -Logfile /tmp/vuln_rdsapp_target.log -S vuln_rdsapp_target -m /vuln_rdsapp_target/entrypoint.sh
    screen -S vuln_rdsapp_target -X colon "logfile flush 0^M"
    sleep 30
    log "check app url..."
    while ! curl -sv http://localhost:listen_port/cast | tee -a $LOGFILE; do
        log "failed to connect to app url http://localhost:listen_port/cast - retrying"
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