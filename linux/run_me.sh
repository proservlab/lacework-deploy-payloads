#!/bin/bash

# variable from jinja2 template 
ENVIRONMENT="%%{ environment }%%"
DEPLOYMENT="%%{ deployment }%%"
ATTACKER_INSTANCES="%%{ attacker_instances }%%"
TARGET_INSTANCES="%%{ target_instances }%%"
ATTACKER_K8S_SERVICES="%%{ attacker_k8s_services }%%"
TARGET_K8S_SERVICES="%%{ target_k8s_services }%%"

echo "${ENVIRONMENT}:${DEPLOYMENT}" > /tmp/run_me.log
echo "${ATTACKER_INSTANCES}" | base64 -d > /tmp/attacker_instances.log
echo "${TARGET_INSTANCES}" | base64 -d > /tmp/target_instances.log
echo "${ATTACKER_K8S_SERVICES}" | base64 -d >> /tmp/attacker_k8s_services.log
echo "${TARGET_K8S_SERVICES}" | base64 -d >> /tmp/target_k8s_services.log