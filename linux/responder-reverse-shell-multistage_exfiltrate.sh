#!/bin/bash

# disable pager
export AWS_PAGER=""

if ! command -v jq; then
  curl -LJ -o /usr/local/bin/jq https://github.com/jqlang/jq/releases/download/jq-1.7/jq-linux-amd64 && chmod 755 /usr/local/bin/jq
fi

# Helper function to update AWS configuration and credentials files
configure_aws() {
    local profile=$1
    local access_key=$2
    local secret_key=$3
    local session_token=$4
    local region=$5

    mkdir -p ~/.aws
    if [ ! -z "$access_key" ]; then
        aws configure set aws_access_key_id "$access_key" --profile=$profile
    fi
    if [ ! -z "$secret_key" ]; then
        aws configure set aws_secret_access_key "$secret_key" --profile=$profile
    fi
    if [ ! -z "$session_token" ]; then
        aws configure set aws_session_token "$session_token" --profile=$profile
    fi
    if [ ! -z "$region" ]; then
        aws configure set region "$region" --profile=$profile
    fi
}

# Retrieve and configure current user credentials using AWS CLI
configure_current_user() {
    if command -v aws &> /dev/null; then
        # Export credentials using aws configure export-credentials
        local creds=$(aws configure export-credentials --format env-no-export)

        # Parse the credentials
        local access_key=$(echo "$creds" | grep 'AWS_ACCESS_KEY_ID' | cut -d '=' -f 2)
        local secret_key=$(echo "$creds" | grep 'AWS_SECRET_ACCESS_KEY' | cut -d '=' -f 2)
        local session_token=$(echo "$creds" | grep 'AWS_SESSION_TOKEN' | cut -d '=' -f 2)
        local region=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

        # Use the helper function to configure the 'default' profile
        configure_aws default "$access_key" "$secret_key" "$session_token" "$region"
    else
        # Fallback to environment variables if AWS CLI is not present
        if [ -n "$AWS_ACCESS_KEY_ID" ] && [ -n "$AWS_SECRET_ACCESS_KEY" ]; then
            configure_aws default "$AWS_ACCESS_KEY_ID" "$AWS_SECRET_ACCESS_KEY" "$AWS_SESSION_TOKEN" "$(curl -s http://169.254.169.254/latest/meta-data/placement/region)"
        fi
    fi
}

# Retrieve and configure instance profile credentials
configure_instance_profile() {
    local instance_profile=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/)
    local credentials=$(curl -s http://169.254.169.254/latest/meta-data/iam/security-credentials/$instance_profile)
    local access_key=$(echo "$credentials" | grep "AccessKeyId" | awk -F ' : ' '{ print $2 }' | tr -d ',' | xargs)
    local secret_key=$(echo "$credentials" | grep "SecretAccessKey" | awk -F ' : ' '{ print $2 }' | tr -d ',' | xargs)
    local session_token=$(echo "$credentials" | grep "Token" | awk -F ' : ' '{ print $2 }' | tr -d ',' | xargs)
    local region=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

    configure_aws instance $access_key $secret_key $session_token $region
}

# Retrieve and configure container/web identity credentials using environment variables
configure_container_identity() {
    # Check if running in a container environment with web identity tokens
    if [ -n "$AWS_WEB_IDENTITY_TOKEN_FILE" ]; then
        if command -v aws &> /dev/null; then
            # Export credentials using aws configure export-credentials
            local creds=$(aws configure export-credentials --format env-no-export)

            # Parse the credentials
            local access_key=$(echo "$creds" | grep 'AWS_ACCESS_KEY_ID' | cut -d '=' -f 2)
            local secret_key=$(echo "$creds" | grep 'AWS_SECRET_ACCESS_KEY' | cut -d '=' -f 2)
            local session_token=$(echo "$creds" | grep 'AWS_SESSION_TOKEN' | cut -d '=' -f 2)
            local region=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

            # Use the helper function to configure the 'container' profile
            configure_aws container "$access_key" "$secret_key" "$session_token" "$region"
        fi
    fi
}

configure_current_user
configure_instance_profile
configure_container_identity