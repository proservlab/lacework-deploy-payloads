#!/bin/bash

# variable from jinja2 template 
ENVIRONMENT="%%{ environment }%%"
DEPLOYMENT="%%{ deployment }%%"

touch /tmp/run_me.log