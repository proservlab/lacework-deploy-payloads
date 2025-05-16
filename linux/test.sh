#!/bin/bash
####################################################################
# Example script to demonstrate how to use environment context in a bash script
######################################################################

URL="https://raw.githubusercontent.com/proservlab/lacework-deploy-payloads/main/linux/common.sh"
FUNC=$(mktemp)
curl -LJ -s $URL -o $FUNC
# make the function available in the current shell
if [ $? -ne 0 ]; then
    echo "Failed to download the function. Exiting."
    exit 1
fi

chmod +x $FUNC
. $FUNC

##################################################################################
# Main script starts here
################################################################################

touch /tmp/pwned