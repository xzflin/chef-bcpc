#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

# set a flag to tell shared_functions.sh how to SSH to machines
export BOOTSTRAP_METHOD=vagrant

echo " ____   ____ ____   ____ "
echo "| __ ) / ___|  _ \ / ___|"
echo "|  _ \| |   | |_) | |    "
echo "| |_) | |___|  __/| |___ "
echo "|____/ \____|_|    \____|"
echo
echo "BCPC Vagrant BootstrapV2 0.2"
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
source ../shared/shared_functions.sh
export REPO_ROOT=$REPO_ROOT

# Source the bootstrap configuration defaults and overrides.
# If the overrides file is at the previous expected location of bootstrap.sh,
# move it and notify the user.
if [[ -f "$REPO_ROOT/bootstrap/config/bootstrap_config.sh" ]]; then
  if [[ ! -f "$REPO_ROOT/bootstrap/config/bootstrap_config.sh.overrides" ]]; then
    echo "Performing one-time move of bootstrap_config.sh to bootstrap_config.sh.overrides..."
    mv $REPO_ROOT/bootstrap/config/bootstrap_config.sh $REPO_ROOT/bootstrap/config/bootstrap_config.sh.overrides
  else
    echo "ERROR: both bootstrap_config.sh and bootstrap_config.sh.overrides exist!" >&2
    echo "Please move all overrides to bootstrap_config.sh.overrides and remove bootstrap_config.sh!" >&2
    exit 1
  fi
fi

BOOTSTRAP_CONFIG_DEFAULTS="$REPO_ROOT/bootstrap/config/bootstrap_config.sh.defaults"
BOOTSTRAP_CONFIG_OVERRIDES="$REPO_ROOT/bootstrap/config/bootstrap_config.sh.overrides"
if [[ -f $BOOTSTRAP_CONFIG_DEFAULTS ]]; then source $BOOTSTRAP_CONFIG_DEFAULTS; fi
if [[ -f $BOOTSTRAP_CONFIG_OVERRIDES ]]; then source $BOOTSTRAP_CONFIG_OVERRIDES; fi

# Perform preflight checks to validate environment sanity as much as possible.
echo "Performing preflight environment validation..."
source $REPO_ROOT/bootstrap/shared/shared_validate_env.sh

# Test that Vagrant is really installed and of an appropriate version.
echo "Checking VirtualBox and Vagrant..."
source $REPO_ROOT/bootstrap/vagrant_scripts/vagrant_test.sh

# Configure and test any proxies configured.
if [[ ! -z $BOOTSTRAP_HTTP_PROXY ]] || [[ ! -z $BOOTSTRAP_HTTPS_PROXY ]] ; then
  echo "Testing configured proxies..."
  source $REPO_ROOT/bootstrap/shared/shared_proxy_setup.sh
fi

# Do prerequisite work prior to starting build, downloading files and
# creating local directories.
echo "Downloading necessary files to local cache..."
source $REPO_ROOT/bootstrap/shared/shared_prereqs.sh

# Terminate existing BCPC VMs.
echo "Shutting down and unregistering VMs from VirtualBox..."
$REPO_ROOT/bootstrap/vagrant_scripts/vagrant_clean.sh

# Create VMs in Vagrant and start them.
echo "Starting local Vagrant cluster..."
$REPO_ROOT/bootstrap/vagrant_scripts/vagrant_create.sh

# Install and configure Chef on all Vagrant hosts.
echo "Installing and configuring Chef on all nodes..."
$REPO_ROOT/bootstrap/shared/shared_configure_chef.sh

# Dump out useful information for users.
$REPO_ROOT/bootstrap/vagrant_scripts/vagrant_print_useful_info.sh

