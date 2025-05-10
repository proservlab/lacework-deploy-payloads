#!/bin/bash

get_base64gzip() {
  local payload="$1"
  echo $payload | base64 -d | gunzip
}

export -f get_base64gzip