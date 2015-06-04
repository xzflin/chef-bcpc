#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

if [ ! -z "$BOOTSTRAP_HTTP_PROXY" ]; then
  export http_proxy=http://${BOOTSTRAP_HTTP_PROXY}
   
  curl -s --connect-timeout 10 http://www.google.com > /dev/null && true
  if [[ $? != 0 ]]; then
    echo "Error: proxy $BOOTSTRAP_HTTP_PROXY non-functional for HTTP requests" >&2
    exit 1
  fi
fi

if [ ! -z "$BOOTSTRAP_HTTPS_PROXY" ]; then
  export https_proxy=https://${BOOTSTRAP_HTTPS_PROXY}
  curl -s --connect-timeout 10 https://github.com > /dev/null && true
  if [[ $? != 0 ]]; then
    echo "Error: proxy $BOOTSTRAP_HTTPS_PROXY non-functional for HTTPS requests" >&2
    exit 1
  fi
fi
