#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

. $REPO_ROOT/bootstrap/shared/shared_functions.sh

load_configs
# Set this to max value to ensure leftover mon VMs are destroyed
export CLUSTER_NODE_COUNT_OVERRIDE=6

cd $REPO_ROOT/bootstrap/vagrant_scripts
if [[ -n "$MACHINE_NAME_PREFIX" ]]; then
    vagrant status | awk -v prefix="^${MACHINE_NAME_PREFIX}" \
        '$1 ~ prefix {print $1}' | xargs vagrant destroy -f
else
    vagrant destroy -f
fi
