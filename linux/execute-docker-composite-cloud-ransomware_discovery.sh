#!/bin/bash

LOGFILE=/tmp/attacker_compromised_credentials_discovery.sh.log
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

log "Setting User-agent: AWS_EXECUTION_ENV=discovery"
export AWS_EXECUTION_ENV="discovery"

log "Starting..."
log "Discovery access attacker simulation..."
log "Current IP: $(curl -s http://icanhazip.com)"
opts="--output json --color off --no-cli-pager"
for REGION in $(aws ec2 describe-regions --output text | cut -f4); do
    log "Discovery using AWS_REGION: $REGION"
    log "Running: aws iam list-users $opts --region \"$REGION\""
    aws iam list-users $opts --region "$REGION" >> $LOGFILE 2>&1
    log "Running: aws s3api list-buckets $opts --region \"$REGION\""
    aws s3api list-buckets $opts --region "$REGION" >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-elastic-gpus $opts --region \"$REGION\""
    aws ec2 describe-elastic-gpus $opts --region "$REGION" >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-hosts $opts --region \"$REGION\""
    aws ec2 describe-hosts $opts --region "$REGION" >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-images --filters \"Name=name,Values=ubuntu-pro-server/images/*20.04*\" $opts --region \"$REGION\""
    aws ec2 describe-images --filters "Name=name,Values=ubuntu-pro-server/images/*20.04*" $opts --region "$REGION" >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-network-acls $opts --region \"$REGION\""
    aws ec2 describe-network-acls $opts --region "$REGION" >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-reserved-instances $opts --region \"$REGION\""
    aws ec2 describe-reserved-instances $opts --region "$REGION" >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-security-groups $opts --region \"$REGION\""
    aws ec2 describe-security-groups $opts --region "$REGION" >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-snapshots $opts --region \"$REGION\""
    aws ec2 describe-snapshots $opts --region "$REGION" >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-volumes $opts --region \"$REGION\""
    aws ec2 describe-volumes $opts --region "$REGION" >> $LOGFILE 2>&1
    log "Running: aws ec2 describe-vpcs $opts --region \"$REGION\""
    aws ec2 describe-vpcs $opts --region "$REGION" >> $LOGFILE 2>&1
done

log "Done."