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
$PACKAGE_MANAGER update >/dev/null 2>&1 || true 
$PACKAGE_MANAGER install -y curl jq openssl procps >/dev/null 2>&1 || true

URL="https://raw.githubusercontent.com/proservlab/lacework-deploy-payloads/main/linux/common.sh"
FUNC=$(mktemp)
curl -LJ -s $URL -o $FUNC
# make the function available in the current shell
if [ $? -ne 0 ]; then
    json=$(printf '{"session_id": "%s", "task": "%s", "stdout": "", "stderr": "%s", "returncode": %d}\n' "$SESSION_ID", "$TASK", "Failed to download common.sh functions","1"); 
    echo $json 1>&2;
fi

chmod +x $FUNC
. $FUNC

##################################################################################
# Main script starts here
################################################################################

touch /tmp/pwned

# generate an error
command_not_found