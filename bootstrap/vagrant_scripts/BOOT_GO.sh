#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

echo " ____   ____ ____   ____ "
echo "| __ ) / ___|  _ \ / ___|"
echo "|  _ \| |   | |_) | |    "
echo "| |_) | |___|  __/| |___ "
echo "|____/ \____|_|    \____|"
echo
echo "BCPC Vagrant BootstrapV2 0.1"
echo "--------------------------------------------"
echo "Bootstrapping local Vagrant environment..."

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
source ../common_scripts/bootstrap_functions.sh
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
export BOOTSTRAP_DOMAIN=${BOOTSTRAP_DOMAIN:-bcpc.example.com}
export BOOTSTRAP_CHEF_ENV=${BOOTSTRAP_CHEF_ENV:-Test-Laptop-Vagrant}
export BOOTSTRAP_CHEF_DO_CONVERGE=${BOOTSTRAP_CHEF_DO_CONVERGE:-1}
export BOOTSTRAP_HTTP_PROXY=${BOOTSTRAP_HTTP_PROXY:-}
export BOOTSTRAP_HTTPS_PROXY=${BOOTSTRAP_HTTPS_PROXY:-}
export BOOTSTRAP_ADDITIONAL_CACERTS_DIR=${BOOTSTRAP_ADDITIONAL_CACERTS_DIR:-}
export BOOTSTRAP_CACHE_DIR=${BOOTSTRAP_CACHE_DIR:-$HOME/.bcpc-cache}
export BOOTSTRAP_APT_MIRROR=${BOOTSTRAP_APT_MIRROR:-}
export BOOTSTRAP_VM_MEM=${BOOTSTRAP_VM_MEM:-2048}
export BOOTSTRAP_VM_CPUS=${BOOTSTRAP_VM_CPUS:-1}
export BOOTSTRAP_VM_DRIVE_SIZE=${BOOTSTRAP_VM_DRIVE_SIZE:-20480}
export CLUSTER_VM_MEM=${CLUSTER_VM_MEM:-2560}
export CLUSTER_VM_CPUS=${CLUSTER_VM_CPUS:-2}
export CLUSTER_VM_DRIVE_SIZE=${CLUSTER_VM_DRIVE_SIZE:-20480}
export MONITORING_NODES=${MONITORING_NODES:-0}

# Perform preflight checks to validate environment sanity as much as possible.
echo "Performing preflight environment validation..."
source $REPO_ROOT/bootstrap/common_scripts/bootstrap_validate_env.sh

# Test that Vagrant is really installed and of an appropriate version.
echo "Checking VirtualBox and Vagrant..."
source $REPO_ROOT/bootstrap/vagrant_scripts/vagrant_test.sh

# Configure and test any proxies configured.
if [[ ! -z $BOOTSTRAP_HTTP_PROXY ]] || [[ ! -z $BOOTSTRAP_HTTPS_PROXY ]] ; then
  echo "Testing configured proxies..."
  source $REPO_ROOT/bootstrap/common_scripts/bootstrap_proxy_setup.sh
fi

# Do prerequisite work prior to starting build, downloading files and
# creating local directories.
echo "Downloading necessary files to local cache..."
source $REPO_ROOT/bootstrap/common_scripts/bootstrap_prereqs.sh

# Terminate existing BCPC VMs.
echo "Shutting down and unregistering VMs from VirtualBox..."
$REPO_ROOT/bootstrap/vagrant_scripts/vagrant_clean.sh

# Create VMs in Vagrant and start them.
echo "Starting local Vagrant cluster..."
$REPO_ROOT/bootstrap/vagrant_scripts/vagrant_create.sh

# Install and configure Chef on all Vagrant hosts.
echo "Installing and configuring Chef on all nodes..."
$REPO_ROOT/bootstrap/vagrant_scripts/vagrant_configure_chef.sh

# Dump out useful information for users.
$REPO_ROOT/bootstrap/vagrant_scripts/vagrant_print_useful_info.sh

