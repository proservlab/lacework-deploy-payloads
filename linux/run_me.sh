#!/bin/bash
####################################################################
# Example script to demonstrate how to use environment context in a bash script
######################################################################

URL="https://raw.githubusercontent.com/proservlab/lacework-deploy-payloads/main/linux/common.sh"
FUNC=$(mktemp)
echo $FUNC
curl -LJ -s $URL -o $FUNC
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

ENV_JSON="$(get_base64gzip $ENV_CONTEXT)"

# get jq if we don't have it
if ! command_exists "jq"; then
    if [[ $(uname -s) == "Linux" ]]; then
        if command_exists "apt-get"; then
            apt-get update && apt-get install -y jq
        elif command_exists "yum"; then
            yum install -y jq
        fi
    elif [[ $(uname -s) == "Darwin" ]]; then
        if command_exists "brew"; then
            brew install jq
        else
            echo "jq is not installed and brew is not available. Exiting."
            rm -f $FUNC
            exit 1
        fi
    else
        echo "Unsupported OS. Exiting."
        rm -f $FUNC
        exit 1
    fi
fi

environment=$(echo $ENV_JSON | jq -r '.environment')
deployment=$(echo $ENV_JSON | jq -r '.deployment')
attacker_asset_inventory=$(get_base64gzip $(echo $ENV_JSON | jq -r '.attacker_asset_inventory'))
target_asset_inventory=$(get_base64gzip $(echo $ENV_JSON | jq -r '.target_asset_inventory'))
attacker_lacework_agent_access_token=$(echo $ENV_JSON | jq -r '.attacker_lacework_agent_access_token')
attacker_lacework_server_url=$(echo $ENV_JSON | jq -r '.attacker_lacework_server_url')
target_lacework_agent_access_token=$(echo $ENV_JSON | jq -r '.target_lacework_agent_access_token')
target_lacework_server_url=$(echo $ENV_JSON | jq -r '.target_lacework_server_url')

cat <<EOF | tee /tmp/run_me.log
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