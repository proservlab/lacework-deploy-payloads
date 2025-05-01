#!/bin/bash

LOGFILE=/tmp/attacker_compromised_credentials_baseline.sh.log
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

log "Starting..."
log "Baseline access for account"
log "Current IP: $(curl -s http://icanhazip.com)"
x=10
opts="--output json --color off --no-cli-pager"
while [ $x -gt 0 ]; 
do 
    log "Running: aws sts get-caller-identity $opts"
    aws sts get-caller-identity $opts >> $LOGFILE 2>&1
    log "Running: aws iam list-users $opts"
    aws iam list-users $opts >> $LOGFILE 2>&1
    log "Running: aws s3api list-buckets $opts"
    aws s3api list-buckets $opts >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-instances $opts"
    aws ec2 describe-instances $opts >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-images --filters \"Name=name,Values=ubuntu-pro-server/images/*20.04*\" $opts"
    aws ec2 describe-images --filters "Name=name,Values=ubuntu-pro-server/images/*20.04*" $opts >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-volumes $opts"
    aws ec2 describe-volumes $opts >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-vpcs $opts"
    aws ec2 describe-vpcs $opts >> $LOGFILE 2>&1
    x=$(($x-1))
done

log "Done."