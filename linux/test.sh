#!/bin/bash
####################################################################
# Example script to demonstrate how to use environment context in a bash script
######################################################################

# make sure we have the required packages installed
if command -v "apt-get" >/dev/null 2>&1; then
    export PACKAGE_MANAGER="apt-get"
    export RETRY="-o Acquire::Retries=10"
elif command -v "yum" >/dev/null 2>&1; then
    export PACKAGE_MANAGER="yum"
    export RETRY="--setopt=retries=10"
fi

echo "running: $PACKAGE_MANAGER update && $PACKAGE_MANAGER install -y curl jq openssl procps"
$PACKAGE_MANAGER update && $PACKAGE_MANAGER install -y curl jq openssl procps

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