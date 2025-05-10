#!/bin/bash

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

get_base64gzip() {
  local payload="$1"
  echo $payload | base64 -d | gunzip
}

export -f get_base64gzip