#!/bin/bash
####################################################################
# Example script to demonstrate how to use environment context in a bash script
######################################################################

URL="https://raw.githubusercontent.com/proservlab/lacework-deploy-payloads/main/linux/common.sh"
FUNC=$(mktemp)
curl -LJ -s $URL > $FUNC

# make the function available in the current shell
if [ $? -ne 0 ]; then
    echo "Failed to download the function. Exiting."
    exit 1
fi

chmod +x $FUNC
. $FUNC

# environment context 
if [ -z "$ENV_CONTEXT" ]; then
    echo "ENV_CONTEXT is not set. Exiting."
    rm -f $FUNC
    exit 1
fi

ENV_CONTENT="$(get_base64gzip $ENV_CONTEXT)"

# get jq if we don't have it
if ! command -v jq; then
    if [ uname -a | grep -q "Linux" ]; then
        if command -v apt-get; then
            apt-get update && apt-get install -y jq
        elif command -v yum; then
            yum install -y jq
        fi
    fi
fi

environment=$(echo $ENV_CONTEXT | jq -r '.environment')
deployment=$(echo $ENV_CONTEXT | jq -r '.deployment')
attacker_asset_inventory=$(echo $ENV_CONTEXT | jq -r '.attacker_asset_inventory' | get_base64gzip)
target_asset_inventory=$(echo $ENV_CONTEXT | jq -r '.target_asset_inventory' | get_base64gzip)
attacker_lacework_agent_access_token=$(echo $ENV_CONTEXT | jq -r '.attacker_lacework_agent_access_token' | get_base64gzip)
attacker_lacework_server_url=$(echo $ENV_CONTEXT | jq -r '.attacker_lacework_server_url' | get_base64gzip)
target_lacework_agent_access_token=$(echo $ENV_CONTEXT | jq -r '.target_lacework_agent_access_token' | get_base64gzip)
target_lacework_server_url=$(echo $ENV_CONTEXT | jq -r '.target_lacework_server_url' | get_base64gzip)

cat <<EOF > /tmp/run_me.log
environment: $environment
deployment: $deployment
attacker_asset_inventory: $attacker_asset_inventory
target_asset_inventory: $target_asset_inventory
attacker_lacework_agent_access_token: $attacker_lacework_agent_access_token
attacker_lacework_server_url: $attacker_lacework_server_url
target_lacework_agent_access_token: $target_lacework_agent_access_token
target_lacework_server_url: $target_lacework_server_url
EOF
echo "${ENV_CONTENT}" > /tmp/run_me.log
rm -f $FUNC
