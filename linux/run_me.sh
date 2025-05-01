#!/bin/bash

# variable from jinja2 template 
ENVIRONMENT="%%{ environment }%%"
DEPLOYMENT="%%{ deployment }%%"

echo "${ENVIRONMENT}:${DEPLOYMENT}" > /tmp/run_me.log