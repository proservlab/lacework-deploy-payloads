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
screen -S vuln_cloudsql_app_target -X quit
screen -wipe
truncate -s 0 /tmp/vuln_cloudsql_app_target.log
log "removing previous app directory"
rm -rf /vuln_cloudsql_app_target
log "building app directory"
mkdir -p /vuln_cloudsql_app_target/templates
cd /vuln_cloudsql_app_target
echo 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 | base64 -d | gunzip > app.py
echo H4sIAAAAAAAA/3LLSSzOtrU11jPQM+JKA3HiEwsyQQKGXAVF+SX5SaVptrYmekamekZcBZW5lcWFOba2hnqGegZcAAAAAP//AQAA//+Z1JPKPAAAAA== | base64 -d | gunzip > requirements.txt
echo H4sIAAAAAAAA/4xX227jvBG+51MQ9oUkwFF6ulgEUFHHcYqgzqG2s+0iCBiaGtncpUiFpJK4Qd69oEQdvL/tRDemht8cOPNxRh5inhdKW1yWPEXtm1DrNZdrlGmV40xQ86vZuXQvyL8o06yKbb41zwINcaXiX2PQulG8oJauqIGp1kp3nn4aJbs3s20tGiM6eamF4KtYw3MJxrYQYBqsqaNcK7UWEDOhyjR2vpmSEphVbQSTRjDCV3fLbQF7NPGO6ZxKugbdnMoDaWk3DY6pvCgtEJBrLgEdgllNpXGrg4gUMloKu8dVvOujUSA5WJpSSxFiGlKQllNhRrjQ6icwS3iKk8ZqGCFniWh4xkkXTJNPE8/rRRj1bcUaMg1mEza6EXIVkdzt8v9Bl1CsVs4n6lKedJshL4jdFpD4pMd386vv4+V0hEHSlQDCaU6ci2SpSxhFCNGiwEnNtJAQSXMgJHJSV9OMrx+CxXQyny7Jv6Y/gkecYGVikC9cKxmvwYb97VHDktiqXyDJBt7Cv/4litAQf90gGmL37NoN2IbKNRC74YaYsgBNaldEU5mqnBiruVwHVdYmGqgFTPGiguDrmlmYCQ7SovoHJ7u8i2uwxy5Av3AGkwoa9uqU9NYRMjWMUMZUKS2BnHKBE9wv7F4MSlekNKBdvqtI9mBiUwhuw+AfQfTwp0eEUAoZpoyBMc3hX0AbrmToX3kanSGXvCE+L7lIsd0A1mBUqRngypfKKmGtgL1+XCn5WLKBZ7U5fe/4/XHqS3v63jr7OPX65lRQC8YOvPNxFeRBRxpMoaRxzupaxPtP5W9M8j5woQ3Oqgg/Im/Dllq2puKCboWiaewuaZwCUymEwf3y8uSb4wQa4jlYzeEF8FaVGqe+QWJ/i7iSOAVLuTB1T9ilDro4J+O7O3I/n+HkQA2CdEU2ytggcui72/kSJ5hLGx6Gu74QRBX+Znw9PWranb02fb+Yzj/HN+zy4YwXi//czi+OqhTUmFelU69Sdw5ydXdcSfMXaoHwwqvdn8+uJp9qlSvBWas0mVbZOoxn4DKFUNcrHoLZ1fn1j8W/Z2R6Mz6fTclkNh3Pl9P/Lsnd7P6fVzdVcwn+HCC0WMzIZFy3moLaTUxXxv2GQTWHzLM4YSpfcQnpCaMnq1KmAuIC8iBCr9xusCpAhrWVEQ5egwhTg7P6rmXxq+YWQn+MqgNlpaw5ZVXDVHcZ9rDOoYeY09wfHr9wipuo3Hx526KhGy14DdaphRE++Xs78ztDJp606zPfQ93u2SdYdwmb6dFAmh7sno75o5504I0O+kJHuaRHvf7eEDfs6nfQek70cekq8behL907vHr7h6aeh0T+15fCnRIN+1c/6bJbjd3dcniK+w7MqulCOu2wbboTJY3VJbN4sZhVMmbfXHs3IvZq/iPBqVt4cx8BHhazDbBfVQfxjfiSCgPt9gtonm1JrlLwFr9XkmuVQuyIR25ub6YVvErqb1OokvU752+sCJ3jZOfajxA+/Pyx1kfAbel9uY9Bla7DuJ0vjwL7RDkCM0YkzL4dxbAN1QZsEpQ2+5av/hYcR5faKM0ENSZpk1jJTHzBmZ1U62MW3EDaId8eSjkaug7g8ruPi3VP2MvFmuu/s9F3hM/52AIPMbIDfJGTxwIyxn0vvffucsBocIZ9s92R74QTnNXhNJCP3Tv+FXoPj9SoJnh/2n6Cbznem7afqexw/Sh0f1vc8zi+GyM+Qe1h/HH81zh/1MbXWI9qs91Ucl+Ntcz9YaoWMbwBKy2Eg8V0Np0s8VPGtbE3NIenEX4StFu7g1JmQVcCfDm/vcZPjBr7NIgQcgsiuHF/Bh4eUaY01uoVc+kPHGdg2YYK0bT4ViGmRQEyDdtr/h60MQRnzsrDoBUMHkc4aKJqdpv3anMnzAaxIxw8fkQIFdp9ULZRRE263P9pAy5BvaR50f8BAAD//wEAAP//9NMUEXYQAAA= | base64 -d | gunzip > test.py
echo H4sIAAAAAAAA/3RTwW7jNhC98yum9kESYFNAeykC6JC47akLLOLsmaDJkcWFRCrDkYMgyL8vKMqOs3B8EWm+9+bNI2f9Rz1Fqg/O1+hPML5yF/xfQrhhDMSg6ThqiihaCgMcQzj2KE0fJgsLIqIh5EF7fUQSa7gG6om7M86EYZwYFfqj8/gbMCTknx+SdHIGlTYmTJ7FV5JM2se0+hJhsdVTzzdsyc9+zgQ1IGurWQthCC16drqPGxgp/ETDyllozqplJZKSInyG5sOMJHyeMHKUj3lRVtdakrAljF155lZCrGFHqBlBw36OE77lPMH0Dj2L/IHmc9oygxfsPqe2m6HlVcXmal0JISy2oI3BGFWWUyek6IIvl62z1Z0AAFjDw+R6C9whEMYwkUHwekAI7fxnJsDClzNpPm+gXS2ZxfrtI733OlNi/XYp9l4v/Fj3mjHyail+P5v8shBhHIOPqVjOR97uarmP5m2VrK3uZofv1aLBE/mLlBz1ax+0lekJSIsmWCyLH0//bf8uUnSuBaUSXSloGlgpNWjnlVrlvOZRIWguYyPv6TgN6Pn7fFJajIbcyC74piBMDhFih30PvYuMHqmorqSktlbpRaMsttsw8ThxsQGbOirO25ly67c81aaYZzY+91sThoPzaLdGbw+Ttz3KEYdiAx32Y1OMmjvgAFkZ7AEMEqfmk5ymY4TmbG7+JHuxrJYre0QmhyeE1zARpBQPOiKY4D2a1DZYZO36mAfy82ufNf55ULt/H59SiDdvs7AHdW1pv/9f7e5z5lFm2/PBi+MOwoi+zJANFC9FBTpCe3fJq5Uv5BjLpWolfgEAAP//AQAA//9flO57EAUAAA== | base64 -d | gunzip > get-cloudsql-cert.py
echo H4sIAAAAAAAA/5ySwY7aMBRF93zF21SZjKJR2y2beoIBl8RQ22E6K/QILrFI7MqYkfj7ygGaaTuqqu5ecs/NPYvkghJFYUIUeSSSApsCXyqgX5lUEnbbjcVOj0eVpMPDtaPIY/F7ocZjgDuzg5JOWFUyrvqUV0UBpFLLDeO5oCXlKvtm/DFw7DSsicjnRNx9+Pg+zVp8623doMc6aP9ntBKsJOIZFvQ5LqfpeKRExfNBMUqNR4xLKhQwrpZXzZ8GGdxWM/hlKYU1KSoqRwAAd8mTaVuDXZJBIhsMVvt4fsZOH0E9wML4Q5JmV7jQzqLfRYKbzp371ndXv0Imeuq8PoYYLXTb6h66FqGsc3ce4H4m5hPnGrTxKp0Ne9dpfwZZuxAG+AnbcLFbOG3NPl4rfNEt5I0+uJeB5KZu4vTFs25c24/wswsIVXPyOLAz7fy+JxUetInH3BzQn0Ce2tPACVOj37mbIrbbi++iQQvcOWu0BWnsvknS8WgmCFdQSTKjsORw/3APagnJbrs5HbVPPiUJCPqlYoKClMWNJ0UBK8HWrKAzKmPx+n/+W/2tOYPdrfPufzf/8o1pUcn5q/74BwAAAP//AQAA//85olOdfAMAAA== | base64 -d | gunzip > bootstrap.sql
echo H4sIAAAAAAAA/1JW1E/KzNNPSizO4OJKrSjILypRcPNxDPaOdwwIsNUvK83Ji0/OyS9NKS7MiU8sKIgvSSxKTy3RTywo0CuoRNXh4uoU6m5rwJWWk1icrVBUmqegm6FgoAeGCroFCmaWAAAAAP//AQAA//+NYwnabgAAAA== | base64 -d | gunzip > entrypoint.sh
echo H4sIAAAAAAAA/7JRdPF3DokMcFXIKMnNseOygVJJ+SmVdlylxalFeYm5qVYK1dUKMI5Cba2Ogk2iQkZRapqtEkiiKCc+Lb9IQz0nPz2/tERdU6G2VskOwrHRT7TjstGHGGejDzYdAAAA//8BAAD//+vjW6h0AAAA | base64 -d | gunzip > templates/index.html
echo H4sIAAAAAAAA/4yRvW6EMAyAd57CHVhrsVtZaDuhtsMtNxoSlEj8SMHLCfHup1yCDgkOXRYr9hf7U0wfX3/l5fr/DVb6TmW0BsNaZQAAJE46o0qeBCo3CWFMZIQRonrUt8TaYgvaYm3BdXgB6ZD45yUmrPpxfhL45d4Qit3XKz4tl5Y9N2L8AUO4HTjn0I4emtDPDTHmy5mcVvP84D7bIBkGwLIQin5Ndvwm2Kzih/RO3Qw62CdhwvS1hHELhHGBdwAAAP//AQAA//+k+Kt32AEAAA== | base64 -d | gunzip > templates/cast.html
    
log "updating entrypoing permissions"
chmod 755 entrypoint.sh

log "installing requirements..."
python3 -m pip install -r requirements.txt >> $LOGFILE 2>&1
log "requirements installed"
    
log "gettting cloudsql cert"
python3 get-cloudsql-cert.py >> $LOGFILE 2>&1
log "cloudsql cert complete"

log "running mysql boostrap..."
mysql --ssl-ca=cloudsql-combined-ca-bundle.pem --ssl-mode=REQUIRED -h db_private_ip -udb_user -pdb_password < bootstrap.sql  >> $LOGFILE 2>&1
log "mysql boostrap complete"

START_HASH=$(sha256sum --text /tmp/payload_$SCRIPTNAME | awk '{ print $1 }')
while true; do
    log "starting app"
    screen -S vuln_cloudsql_app_target -X quit
    screen -wipe
    screen -d -L -Logfile /tmp/vuln_cloudsql_app_target.log -S vuln_cloudsql_app_target -m /vuln_cloudsql_app_target/entrypoint.sh
    screen -S vuln_cloudsql_app_target -X colon "logfile flush 0^M"
    sleep 30
    log "check app url..."
    while ! curl -sv http://localhost:69/cast | tee -a $LOGFILE; do
        log "failed to connect to app url http://localhost:69/cast - retrying"
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