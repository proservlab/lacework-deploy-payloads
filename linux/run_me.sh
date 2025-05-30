#!/bin/bash
####################################################################
# Example script to demonstrate how to use environment context in a bash script
######################################################################

# make sure we have the required packages installed
if command -v "apt-get" >/dev/null 2>&1; then
    export PACKAGE_MANAGER="apt-get"
    export RETRY="-o Acquire::Retries=10"
elif command -v "yum" >/dev/null 2>&1; then
    export PACKAGE_MANAGER="yum"
    export RETRY="--setopt=retries=10"
fi

echo "running: $PACKAGE_MANAGER update && $PACKAGE_MANAGER install -y curl jq openssl procps"
$PACKAGE_MANAGER update >/dev/null 2>&1 || true 
$PACKAGE_MANAGER install -y curl jq openssl procps >/dev/null 2>&1 || true

URL="https://raw.githubusercontent.com/proservlab/lacework-deploy-payloads/main/linux/common.sh"
FUNC=$(mktemp)
curl -LJ -s $URL -o $FUNC
# make the function available in the current shell
if [ $? -ne 0 ]; then
    json=$(printf '{"session_id": "%s", "task": "%s", "stdout": "", "stderr": "%s", "returncode": %d}\n' "$SESSION_ID", "$TASK", "Failed to download common.sh functions","1"); 
    echo $json 1>&2;
fi

chmod +x $FUNC
. $FUNC

##################################################################################
# Main script starts here
################################################################################

# start a random sleep to avoid multiple executions at the same time
log "Starting random sleep"
random_sleep 300

# check if package manager is busy
wait_for_package_manager

# check and install required packages
if ! command_exists jq; then install_packages "jq"; fi
if ! command_exists curl; then install_packages "curl"; fi

# example syntax to run script in a loop until the payload changes
# cat <<'EOF' | base64 | main_loop

# environment context is passed in as a base64 encoded gzip string
if [ -z "$ENV_CONTEXT" ]; then
    log "ENV_CONTEXT is not set. Exiting."
    rm -f $FUNC
    exit 1
fi

ENV_JSON="$(get_base64gzip $ENV_CONTEXT)"

if [ -z "$TAG" ]; then
    log "TAG is not set."
fi

tag=$TAG
environment=$(echo $ENV_JSON | jq -r '.environment')
deployment=$(echo $ENV_JSON | jq -r '.deployment')
attacker_asset_inventory=$(get_base64gzip $(echo $ENV_JSON | jq -r '.attacker_asset_inventory'))
target_asset_inventory=$(get_base64gzip $(echo $ENV_JSON | jq -r '.target_asset_inventory'))
attacker_lacework_agent_access_token=$(echo $ENV_JSON | jq -r '.attacker_lacework_agent_access_token')
attacker_lacework_server_url=$(echo $ENV_JSON | jq -r '.attacker_lacework_server_url')
target_lacework_agent_access_token=$(echo $ENV_JSON | jq -r '.target_lacework_agent_access_token')
target_lacework_server_url=$(echo $ENV_JSON | jq -r '.target_lacework_server_url')

# $LOGFILE inherited from common.sh
cat <<EOF | tee $LOGFILE
tag: $TAG
environment: $environment
deployment: $deployment
attacker_asset_inventory: $attacker_asset_inventory
target_asset_inventory: $target_asset_inventory
attacker_lacework_agent_access_token: $attacker_lacework_agent_access_token
attacker_lacework_server_url: $attacker_lacework_server_url
target_lacework_agent_access_token: $target_lacework_agent_access_token
target_lacework_server_url: $target_lacework_server_url
EOF
rm -f $FUNC

log "Done."