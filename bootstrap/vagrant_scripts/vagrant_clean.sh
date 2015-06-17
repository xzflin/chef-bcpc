#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

# Set this to max value to ensure leftover mon VMs are destroyed
MONITORING_NODES=3
cd $REPO_ROOT/bootstrap/vagrant_scripts && vagrant destroy -f
