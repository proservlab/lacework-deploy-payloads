#!/bin/bash

# variable from jinja2 template 
ENVIRONMENT="%%{ environment }%%"
DEPLOYMENT="%%{ deployment }%%"
ATTACKER_INSTANCES="%%{ attacker_instances }%%"
ATTACKER_DNS_RECORDS="%%{ attacker_dns_records }%%"
TARGET_INSTANCES="%%{ target_instances }%%"
TARGET_DNS_RECORDS="%%{ target_dns_records }%%"
ATTACKER_K8S_SERVICES="%%{ attacker_k8s_services }%%"
TARGET_K8S_SERVICES="%%{ target_k8s_services }%%"

echo "${ENVIRONMENT}:${DEPLOYMENT}" > /tmp/run_me.log
echo "${ATTACKER_INSTANCES}" | base64 -d | gunzip > /tmp/attacker_instances.log
echo "${ATTACKER_DNS_RECORDS}" | base64 -d | gunzip > /tmp/attacker_dns_records.log
echo "${TARGET_INSTANCES}" | base64 -d | gunzip > /tmp/target_instances.log
echo "${TARGET_DNS_RECORDS}" | base64 -d | gunzip > /tmp/target_dns_records.log
echo "${ATTACKER_K8S_SERVICES}" | base64 -d | gunzip >> /tmp/attacker_k8s_services.log
echo "${TARGET_K8S_SERVICES}" | base64 -d | gunzip >> /tmp/target_k8s_services.log