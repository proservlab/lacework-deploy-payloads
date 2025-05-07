#!/bin/bash

# environment context 
ENV_CONTENT="$(echo $ENV_CONTEXT | base64 -d | gunzip)"

echo "${ENV_CONTENT}" > /tmp/run_me.log
