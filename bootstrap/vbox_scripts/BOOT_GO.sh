#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

echo " ____   ____ ____   ____ "
echo "| __ ) / ___|  _ \ / ___|"
echo "|  _ \| |   | |_) | |    "
echo "| |_) | |___|  __/| |___ "
echo "|____/ \____|_|    \____|"
echo
echo "BCPC VirtualBox BootstrapV2 0.1"
echo "--------------------------------------------"
echo "Bootstrapping local VirtualBox environment..."

while getopts "v" opt; do
  case $opt in
    # verbose
    v)
      set -x
      ;;
  esac
done

# Source common bootstrap functions. This is the only place that uses a
# relative path; everything henceforth must use $REPO_ROOT.
source ../shared/shared_functions.sh
export REPO_ROOT=$REPO_ROOT

# Source the bootstrap configuration file if present.
BOOTSTRAP_CONFIG="$REPO_ROOT/bootstrap/config/bootstrap_config.sh"
if [[ -f $BOOTSTRAP_CONFIG ]]; then
  source $BOOTSTRAP_CONFIG
fi

# Set all configuration variables that are not defined.
# DO NOT EDIT HERE; create bootstrap_config.sh as shown above from the
# template and define variables there.
export BCPC_VM_DIR=${BCPC_VM_DIR:-$HOME/BCPC-VMs}
export BOOTSTRAP_PROXY=${BOOTSTRAP_PROXY:-}
export BOOTSTRAP_CACHE_DIR=${BOOTSTRAP_CACHE_DIR:-$HOME/.bcpc-cache}
export BOOTSTRAP_APT_MIRROR=${BOOTSTRAP_APT_MIRROR:-}
export BOOTSTRAP_VM_MEM=${BOOTSTRAP_VM_MEM:-2048}
export BOOTSTRAP_VM_CPUS=${BOOTSTRAP_VM_CPUS:-1}
export BOOTSTRAP_VM_DRIVE_SIZE=${BOOTSTRAP_VM_DRIVE_SIZE:-20480}
export CLUSTER_VM_MEM=${CLUSTER_VM_MEM:-2560}
export CLUSTER_VM_CPUS=${CLUSTER_VM_CPUS:-2}
export CLUSTER_VM_DRIVE_SIZE=${CLUSTER_VM_DRIVE_SIZE:-20480}

# Perform preflight checks to validate environment sanity as much as possible.
echo "Performing preflight environment validation..."
source $REPO_ROOT/bootstrap/shared/shared_validate_env.sh

# Test that VirtualBox is really installed and of an appropriate version.
# If successful, registers $VBM as the location of VBoxManage.
echo "Checking VirtualBox version..."
source $REPO_ROOT/bootstrap/vbox_scripts/vbox_test.sh

# Configure and test any proxy configured in $BOOTSTRAP_PROXY.
if [[ -z $BOOTSTRAP_PROXY ]]; then
  echo "Testing configured proxy..."
  source $REPO_ROOT/bootstrap/shared/shared_proxy_setup.sh
fi

# Do prerequisite work prior to starting build, downloading files and
# creating local directories.
echo "Downloading necessary files to local cache..."
source $REPO_ROOT/bootstrap/shared/shared_prereqs.sh

# Terminate existing BCPC VMs and clean out $BCPC_VM_DIR.
# (don't source this script because VBoxManage is expected to return non-0)
echo "Shutting down and unregistering VMs from VirtualBox..."
$REPO_ROOT/bootstrap/vbox_scripts/vbox_clean.sh

# Create VMs in VirtualBox and start them
$REPO_ROOT/bootstrap/vbox_scripts/vbox_create.sh
$REPO_ROOT/bootstrap/vbox_scripts/vbox_startvms.sh
#build_snaps.sh
# vbox_install_cluster.sh

cd $BCPC_VM_DIR/bcpc-bootstrap && vagrant ssh -c 'cd $HOME/chef-bcpc && ./wait_and_bootstrap.sh'
