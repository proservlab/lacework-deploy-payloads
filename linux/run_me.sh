#!/bin/bash
####################################################################
# Example script to demonstrate how to use environment context in a bash script
######################################################################
# environment context 
if [ -z "$ENV_CONTEXT" ]; then
    echo "ENV_CONTEXT is not set. Exiting."
    exit 1
fi

ENV_CONTENT="$(echo $ENV_CONTEXT | base64 -d | gunzip)"

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

$environment = $(echo $ENV_CONTEXT | jq -r '.environment')
$deployment = $(echo $ENV_CONTEXT | jq -r '.deployment')
$attacker_asset_inventory = $(echo $ENV_CONTEXT | jq -r '.attacker_asset_inventory' | base64 -d | gunzip)
$target_asset_inventory = $(echo $ENV_CONTEXT | jq -r '.target_asset_inventory' | base64 -d | gunzip)

cat <<EOF > /tmp/run_me.log
environment: $environment
deployment: $deployment
attacker_asset_inventory: $attacker_asset_inventory
target_asset_inventory: $target_asset_inventory
EOF
echo "${ENV_CONTENT}" > /tmp/run_me.log
