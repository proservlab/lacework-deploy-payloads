#!/bin/bash

SCRIPTNAME=iam2enum
LOGFILE=/tmp/$SCRIPTNAME.log
function log {
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1"
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" >> $LOGFILE
}
MAXLOG=2
for i in `seq $((MAXLOG-1)) -1 1`; do mv "$LOGFILE."{$i,$((i+1))} 2>/dev/null || true; done
mv $LOGFILE "$LOGFILE.1" 2>/dev/null || true

help(){
cat <<EOH
usage: $SCRIPTNAME [-h] [--bucket-url=BUCKET_URL]

-h                      print this message and exit
--profile               the aws profile to use (default: default)
EOH
    exit 1
}

for i in "$@"; do
  case $i in
    -h|--help)
        HELP="${i#*=}"
        shift # past argument=value
        help
        ;;
    -p=*|--profile=*)
        PROFILE="${i#*=}"
        shift # past argument=value
        ;;
    *)
      # unknown option
      ;;
  esac
done

if [ -z $PROFILE ]; then
    log "profile not set using default: default"
    PROFILE="default"
fi

opts="--no-cli-pager"

if ! command -v jq; then
  curl -LJ -o /usr/local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64 && chmod 755 /usr/local/bin/jq
fi

#######################
# aws cred setup
#######################

log "public ip: $(curl -s https://icanhazip.com)"

log "available profiles: $(aws configure list-profiles)"

while ! aws configure list-profiles | grep $PROFILE; do
    log "missing profile: $PROFILE"
    log "aws dir listing: $(ls -ltra ~/.aws)"
    log "waiting for profile..."
    sleep 60
done

log "Running: aws sts get-caller-identity --profile=$PROFILE"
aws sts get-caller-identity --profile=$PROFILE $opts >> $LOGFILE 2>&1

log "Getting current account number..."
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --profile=$PROFILE $opts | jq -r '.Account')
log "Account Number: $AWS_ACCOUNT_NUMBER"

#######################
# cloud enumeration
#######################

scout aws --profile=$PROFILE --report-dir /root/scout-report --no-browser | tee -a $LOGFILE