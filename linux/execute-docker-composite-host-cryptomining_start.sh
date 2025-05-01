#!/bin/bash 

SCRIPTNAME="$(basename "$0")"
SCRIPT_DIR="$( cd -- "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
VERSION="0.0.1"

info(){
cat <<EOI
$SCRIPTNAME ($VERSION)

EOI
}

help(){
cat <<EOH
usage: $SCRIPTNAME [-h] --container=[aws-cli|terraform|protonvpn] --script=[baseline.sh|discovery.sh|cloudcrypt|hostcrypto] --env-file=ENV_FILE

--service   the docker container to launch;
--env-file  path to environment variable file. default: .env 
EOH
		exit 1
}

errmsg(){
echo "ERROR: ${1}"
}

warnmsg(){
echo "WARN: ${1}"
}

infomsg(){
echo "INFO: ${1}"
}



for i in "$@"; do
  case $i in
    -h|--help)
        HELP="${i#*=}"
        shift # past argument=value
        help
        ;;
    -c=*|--container=*)
        CONTAINER="${i#*=}"
        shift # past argument=value
        ;;
    -s=*|--script=*)
        SCRIPT="${i#*=}"
        shift # past argument=value
        ;;
    -f=*|--env-file=*)
        ENV_FILE="${i#*=}"
        shift # past argument=value
        ;;
    *)
      # unknown option
      ;;
  esac
done

# check for required
if [ -z "${SCRIPT}" ]; then
    SCRIPT=""
fi

# setup logging
LOGFILE=/tmp/attacker_${CONTAINER}_${SCRIPT}.sh.log
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

if [ -z "${CONTAINER}" ]; then
    errmsg "Required option not set: --container"
    help
elif [ "${CONTAINER}" = "protonvpn" ]; then
    CONTAINER_IMAGE="ghcr.io/tprasadtp/protonvpn:5.2.1"
    DOCKER_OPTS="--detach --device=/dev/net/tun --cap-add=NET_ADMIN"
elif [ "${CONTAINER}" = "torproxy" ]; then
    CONTAINER_IMAGE="dperson/torproxy"
    DOCKER_OPTS="-d --rm --name torproxy -p 9050:9050"
elif [ "${CONTAINER}" = "scoutsuite" ]; then
    CONTAINER_IMAGE="rossja/ncc-scoutsuite:aws-latest"
    DOCKER_OPTS="-i --net=container:protonvpn"
    SCRIPT="scout aws -f --max-workers=1 --no-browser"
elif [ "${CONTAINER}" = "aws-cli" ]; then
    CONTAINER_IMAGE="amazon/aws-cli:latest"
    DOCKER_OPTS="-i --entrypoint=/bin/bash --net=container:protonvpn -w /scripts"
elif [ "${CONTAINER}" = "terraform" ]; then
    CONTAINER_IMAGE="hashicorp/terraform:latest"
    DOCKER_OPTS="-i --entrypoint=/bin/sh --net=container:protonvpn -w /scripts/${SCRIPT}"
    SCRIPT="terraform.sh"
fi

if [ -z "${ENV_FILE}" ]; then
    errmsg "Required option not set: --env-file"
    warnmsg "Using default: ${SCRIPT_DIR}/.env"
    ENV_FILE="${SCRIPT_DIR}/.env"
fi

log "Starting..."

log "Removing existing containers..."
docker stop ${CONTAINER} 2> /dev/null
docker rm ${CONTAINER} 2> /dev/null
docker pull ${CONTAINER_IMAGE}

log "Running docker command: docker run --name=${CONTAINER} ${DOCKER_OPTS} -v \"${SCRIPT_DIR}/${CONTAINER}/scripts\":/scripts --env-file=\"${ENV_FILE}\" ${CONTAINER_IMAGE} ${SCRIPT}"
docker run \
--name=${CONTAINER} \
${DOCKER_OPTS} \
-v "${SCRIPT_DIR}/${CONTAINER}/scripts":/scripts \
--env-file="${ENV_FILE}" \
${CONTAINER_IMAGE} ${SCRIPT}

log "Done."