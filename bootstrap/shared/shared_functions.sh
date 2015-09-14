#!/bin/bash

# Uses Git to find the top level directory so that everything can be referenced
# via absolute paths.
REPO_ROOT=$(git rev-parse --show-toplevel)

if [[ $BOOTSTRAP_METHOD =~ ^vagrant ]]; then 
  do_on_node() {
    NODE=$1
    shift
    COMMAND="${*}"
    vagrant ssh $NODE -c "$COMMAND"
  }
else
  # define it here with whatever we would use to SSH to Packer-booted machines
  :
fi

check_for_envvars() {
  FAILED_ENVVAR_CHECK=0
  REQUIRED_VARS="${@}"
  for ENVVAR in ${REQUIRED_VARS[@]}; do
    if [[ -z ${!ENVVAR} ]]; then
      echo "Environment variable $ENVVAR must be set!" >&2
      FAILED_ENVVAR_CHECK=1
    fi
  done
  if [[ $FAILED_ENVVAR_CHECK != 0 ]]; then exit 1; fi
}
