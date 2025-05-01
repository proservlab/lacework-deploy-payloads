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
    PACKAGES="curl unzip git"
    RETRY="-o Acquire::Retries=10"
elif command -v yum &>/dev/null; then
    export PACKAGE_MANAGER="yum"
    PACKAGES="curl unzip git"
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
screen -S vuln_log4j_app_target -X quit
screen -wipe
truncate -s 0 /tmp/vuln_log4j_app_target.log
    
rm -rf /vuln-log4j-app
mkdir /vuln-log4j-app
cd /vuln-log4j-app

log "creating local files..."
echo H4sIAAAAAAAA/5xWUW/bNhB+16+4qQ+WAI1xCm8r6qntmqVbXpIg8QYMRSHQ0iliIpMcSdkODP/3gZRky5acbNNDIvG++3g83n2+XIkF5CXVT8AWUigDX+xHBBp5luSsxAgU/l2hNl4DELp908/712oulUhRa8+jUkJc8wRJwukCkyT0vE9USqJEZTAYnV2uZSmYIWlJtR6FXoY5YL2WuLUgfO8BALyBOdX44ySR9LkUNIO4jYdQ9aDJA5pgJEcRjEZh48By4MIc+bVs9lFoKsXBvxYNCFpyqcSSZZgRP4LJeOx5tcMjXdJEqxRiyH3f9960ybIGwgS5urlcpygNE3x6ZOVMkLSgSqMh94byjKrsov7Wx9jKsJJ8diFN7d6ympcsBZcQaFIGm00bVmNuDEEIplBipaETjUXXYPvcG8X4Q3Po211C/c1hrrb+tO+UYSoyzPZeHFeNLahDtnfxq0OpICQ1PjjYK4zgOAXkj9mX5F049To7np3B5RrTyiCYAtud20vqAG/rkgPZhNN8f65YaYPw51QXfgT+96kfHR0g7NC0D1GYMYWpuVRKqHujkC4CoyocBGtDlQnC6WHgf4kKUsqhoDwr6/ibxgBRGVkZKFChq1HEDNvTbLfem/qPrS+7Mvvl7rfLWXJ1ay/o/O1PZEzG5PzAdntzN4MYJpPJxBsq0zasl4r1FIbLytQZOIm5ced5CcRtzYv0Cc2gfU04XTD+QC4EN7h+BXRNF/gyQktGbuaPmJovNDVCPQ9H5brsd6oLQ+flK5TX7t/L+dqB7zBHhTzFqbfDDbYwW8gSF8iNhoN4XW93i6zX4ZvNgX27PcR/ulmiUizDIZZ6K3hAU79dcW0oTzFoDGL+GIHNMljNjqC5Ffd1YdYR7HL288cIPn4A5EumBLcH2WnPgfIc90wjJYXQxsnOrsat4hyDGTfgchzDplPw2z6yoU0XTszO5oyf6WKA8RW5SBdZeFoC9v3e295VOOhWE91nYA8ZuQMMuHTaCySDGKQVz85qEEYgsTV0gwkj0NZD9zz623Q7FKRo6brLjk+0fIeWPuGqYCVC8J0mTF+UQmMWhL2iPAJLRuiSstIWThDCBxiHg3D7aEFWihm0TgqpZe8H0eXG/8ON/4pb/4e4ZcutX4lbC5KXlS6GktsQvWifFZae6BJRBj+MT6BMLSUnoyW4ZuZPWlZ4ah/7zBXSp2HzdgspNWkBwb7f8WQhbLe95YElSTLURonnoZg0SW25DZmaaY5XZTk9FsejV/uj6F5WzBQgJPLAbydRq+R2Vlj5IVAN+fudc97cbfvzGtYc+5GXqIoHX31rt4PGIeW3Bt6EuZur9zu73wY/AqoTagxNCyuo8UxVGMF+wTlZKY6PHEPPYzm0gzbEMYySZEEZT5JRfQiWQ4k80M/azszL0GLe7s/XiCzjZgf5ev6tLnYsNfaQ78bj8/pQbqSvuBO72B+7GWXs17IXO+3z/gEAAP//AQAA///fjsskYgwAAA== | base64 -d | gunzip > web.py
echo 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 | base64 -d | gunzip  > ldap.py
echo H4sIAAAAAAAA/wTAsQnFMAwE0F7DHNK5vvZP8BcQOEWIIcESZP2838q6JCIwbM18+t4SA4Tb/z2rjymRCIdbdu+SOBBw+wAAAP//AQAA//8yX5aMPAAAAA== | base64 -d | gunzip > requirements.txt

# install java 8u131
log "checking for jdk1.8.0_131..."
if [ ! -d /usr/java/jdk1.8.0_131/ ]; then
    log "jdk1.8.0_131 not found - installing..."
    wget -c --header "Cookie: oraclelicense=accept-securebackup-cookie" http://download.oracle.com/otn-pub/java/jdk/8u131-b11/d54c1d3a095b4ff2b6607d096fa80163/jdk-8u131-linux-x64.tar.gz
    mkdir -p /usr/java
    sudo tar -xvzf jdk-8u131-linux-x64.tar.gz -C /usr/java
else
    log "jdk1.8.0_131 found - skipping install"
fi
    

# update java path
log "setting up java environment for build..."
export JAVA_HOME=/usr/java/jdk1.8.0_131/
sudo update-alternatives --install /usr/bin/java java $${JAVA_HOME%*/}/bin/java 20000
sudo update-alternatives --install /usr/bin/javac javac $${JAVA_HOME%*/}/bin/javac 20000
    
java -version >> $LOGFILE 2>&1

# download gradle 7.3.1
log "checking for gradle 7.3.1..."
if [ ! -d /opt/gradle/gradle-7.3.1 ]; then
    log "gradle not found - installing..."
    wget https://services.gradle.org/distributions/gradle-7.3.1-bin.zip
    mkdir /opt/gradle
    unzip -d /opt/gradle gradle-7.3.1-bin.zip
else
    log "gradle 7.3.1 found - skipping install" 
fi

# update gradle path
log "updating environment PATH to include gradle..."
export PATH=$PATH:/opt/gradle/gradle-7.3.1/bin
gradle --version >> $LOGFILE 2>&1

# clone the log4shell vulnerable app
log "cloning https://github.com/christophetd/log4shell-vulnerable-app..."
git clone https://github.com/christophetd/log4shell-vulnerable-app
cd log4shell-vulnerable-app
log "running gradle build..."
nohup gradle bootJar --no-daemon &
GRADLE_PID=$!
while kill -0 $GRADLE_PID 2> /dev/null; do
    log "Process is still running..."
    sleep 30
done
log "gradle build complete."
    
ls -ltr build/libs/*.jar >> $LOGFILE 2>&1

# copy java jar
log "Copying java jar.."
cp build/libs/log4shell-vulnerable-app-0.0.1-SNAPSHOT.jar /vuln-log4j-app/log4shell-vulnerable-app-0.0.1-SNAPSHOT.jar >> $LOGFILE 2>&1
    
# change to app root dir
cd /vuln-log4j-app

START_HASH=$(sha256sum --text /tmp/payload_$SCRIPTNAME | awk '{ print $1 }')
while true; do
    log "starting app"
    if pgrep -f "log4shell-vulnerable-app-0.0.1-SNAPSHOT.jar"; then
        kill -9 $(pgrep -f "log4shell-vulnerable-app-0.0.1-SNAPSHOT.jar")
    fi
    screen -S vuln_log4j_app_target -X quit
    screen -wipe
    screen -d -L -Logfile /tmp/vuln_log4j_app_target.log -S vuln_log4j_app_target -m java -jar /vuln-log4j-app/log4shell-vulnerable-app-0.0.1-SNAPSHOT.jar --server.port=listen_port
    screen -S vuln_log4j_app_target -X colon "logfile flush 0^M"
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