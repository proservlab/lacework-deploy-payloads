#!/bin/bash

# variable from jinja2 template 
ENVIRONMENT="%%{ environment }%%"
DEPLOYMENT="%%{ deployment }%%"
ATTACKER_ATTACKER_INVENTORY="%%{ attacker_asset_inventory }%%"
TARGET_ATTACKER_INVENTORY="%%{ target_asset_inventory }%%"

echo "${ENVIRONMENT}:${DEPLOYMENT}" > /tmp/run_me.log
echo "${ATTACKER_ATTACKER_INVENTORY}" | base64 -d | gunzip > /tmp/attacker_asset_inventory.log
echo "${TARGET_ATTACKER_INVENTORY}" | base64 -d | gunzip > /tmp/target_asset_inventory.log