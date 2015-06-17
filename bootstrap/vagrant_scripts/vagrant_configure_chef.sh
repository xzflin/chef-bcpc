#!/bin/bash
# Exit immediately if anything goes wrong, instead of making things worse.
set -e

FAILED_ENVVAR_CHECK=0
REQUIRED_VARS=( BOOTSTRAP_CHEF_DO_CONVERGE BOOTSTRAP_CHEF_ENV BOOTSTRAP_DOMAIN REPO_ROOT )
for ENVVAR in ${REQUIRED_VARS[@]}; do
  if [[ -z ${!ENVVAR} ]]; then
    echo "Environment variable $ENVVAR must be set!" >&2
    FAILED_ENVVAR_CHECK=1
  fi
done
if [[ $FAILED_ENVVAR_CHECK != 0 ]]; then exit 1; fi

# This script does a lot of stuff:
# - installs Chef Server on the bootstrap node
# - installs Chef client on all nodes

# It would be more efficient as something executed in one shot on each node, but
# doing it this way makes it easy to orchestrate operations between nodes. It will be 
# overhauled at some point to not be Vagrant-specific.

do_on_node() {
  NODE=$1
  shift
  COMMAND="${*}"
  vagrant ssh $NODE -c "$COMMAND"
}

cd $REPO_ROOT/bootstrap/vagrant_scripts

# use Chef Server embedded knife instead of the one in /usr/bin
KNIFE=/opt/opscode/embedded/bin/knife

# install and configure Chef Server 12 and Chef 12 client on the bootstrap node
do_on_node bootstrap "sudo dpkg -i \$(find /chef-bcpc-files/ -name chef-server\*deb -not -name \*downloaded | tail -1)"
# move nginx insecure to 4000/TCP is so that Cobbler can run on the regular 80/TCP
do_on_node bootstrap "sudo sh -c \"echo nginx[\'non_ssl_port\'] = 4000 > /etc/opscode/chef-server.rb\""
do_on_node bootstrap "sudo chef-server-ctl reconfigure"
do_on_node bootstrap "sudo chef-server-ctl user-create admin admin admin admin@localhost.com welcome --filename /etc/opscode/admin.pem"
do_on_node bootstrap "sudo chef-server-ctl org-create bcpc BCPC --association admin --filename /etc/opscode/bcpc-validator.pem"
do_on_node bootstrap "sudo chmod 0644 /etc/opscode/admin.pem /etc/opscode/bcpc-validator.pem"
do_on_node bootstrap "sudo dpkg -i \$(find /chef-bcpc-files/ -name chef_\*deb -not -name \*downloaded | tail -1)"

# configure knife on the bootstrap node and perform a knife bootstrap to create the bootstrap node in Chef
do_on_node bootstrap "mkdir -p \$HOME/.chef && echo -e \"chef_server_url 'https://bcpc-bootstrap.$BOOTSTRAP_DOMAIN/organizations/bcpc'\\\nvalidation_client_name 'bcpc-validator'\\\nvalidation_key '/etc/opscode/bcpc-validator.pem'\\\nnode_name 'admin'\\\nclient_key '/etc/opscode/admin.pem'\\\nknife['editor'] = 'vim'\\\ncookbook_path [ \\\"#{ENV['HOME']}/chef-bcpc/cookbooks\\\" ]\" > \$HOME/.chef/knife.rb"
do_on_node bootstrap "$KNIFE ssl fetch"
do_on_node bootstrap "$KNIFE bootstrap -x vagrant -P vagrant --sudo 10.0.100.3"

# Initialize VM lists
vms="vm1 vm2 vm3"
if [ $MONITORING_NODES -gt 0 ]; then
  i=1
  while [ $i -le $MONITORING_NODES ]; do
    mon_vm="vm`expr 3 + $i`"
    mon_vms="$mon_vms $mon_vm"
    i=`expr $i + 1`
  done
fi

# install the knife-acl plugin into embedded knife
do_on_node bootstrap "sudo /opt/opscode/embedded/bin/gem install /chef-bcpc-files/knife-acl-0.0.12.gem"

# rsync the Chef repository into the non-root user (vagrant)'s home directory
do_on_node bootstrap "rsync -a /chef-bcpc-host/* \$HOME/chef-bcpc"

# add the dependency cookbooks from the file cache
do_on_node bootstrap "cp /chef-bcpc-files/cookbooks/*.tar.gz \$HOME/chef-bcpc/cookbooks && cd \$HOME/chef-bcpc/cookbooks && ls -1 *.tar.gz | xargs -I% tar xvzf %"

# build binaries before uploading the bcpc cookbook
# (this step will change later but using the existing build_bins script for now)
do_on_node bootstrap "sudo apt-get update"
# build bins step requires internet access even despite the local cache (thanks setuptools), so configure proxies just for
# this step if necessary ($HOME/proxy_config.sh is created by Vagrant during initial setup and will be empty if no proxies were configured)
do_on_node bootstrap "cd \$HOME/chef-bcpc && sudo bash -c 'source \$HOME/proxy_config.sh && bootstrap/common_scripts/common_build_bins.sh'"

# upload all cookbooks, roles and our chosen environment to the Chef server
# (cookbook upload uses the cookbook_path set when configuring knife on the bootstrap node)
do_on_node bootstrap "$KNIFE cookbook upload apt bcpc chef-client cron logrotate ntp ubuntu yum"
do_on_node bootstrap "cd \$HOME/chef-bcpc/roles && $KNIFE role from file *.json"
do_on_node bootstrap "cd \$HOME/chef-bcpc/environments && $KNIFE environment from file $BOOTSTRAP_CHEF_ENV.json"

# install and bootstrap Chef on cluster nodes
i=1
for vm in $vms $mon_vms; do
  do_on_node $vm "sudo dpkg -i \$(find /chef-bcpc-files/ -name chef_\*deb -not -name \*downloaded | tail -1)"
  do_on_node bootstrap "$KNIFE bootstrap -x vagrant -P vagrant --sudo 10.0.100.1${i}"
  i=`expr $i + 1`
done

# augment the previously configured nodes with our newly uploaded environments and roles
for vm in bootstrap $vms $mon_vms; do
  do_on_node bootstrap "$KNIFE node environment set bcpc-$vm.$BOOTSTRAP_DOMAIN $BOOTSTRAP_CHEF_ENV"
done

do_on_node bootstrap "$KNIFE node run_list set bcpc-bootstrap.$BOOTSTRAP_DOMAIN 'role[BCPC-Bootstrap]'"
do_on_node bootstrap "$KNIFE node run_list set bcpc-vm1.$BOOTSTRAP_DOMAIN 'role[BCPC-Headnode]'"
do_on_node bootstrap "$KNIFE node run_list set bcpc-vm2.$BOOTSTRAP_DOMAIN 'role[BCPC-Worknode]'"
do_on_node bootstrap "$KNIFE node run_list set bcpc-vm3.$BOOTSTRAP_DOMAIN 'role[BCPC-Worknode]'"

# generate actor map
do_on_node bootstrap "cd \$HOME && $KNIFE actor map"
# using the actor map, set bootstrap, vm1 and mon vms (if any) as admins so that they can write into the data bag
do_on_node bootstrap "cd \$HOME && $KNIFE group add actor admins bcpc-bootstrap.$BOOTSTRAP_DOMAIN && $KNIFE group add actor admins bcpc-vm1.$BOOTSTRAP_DOMAIN"
for vm in $mon_vms; do
  do_on_node bootstrap "cd \$HOME && $KNIFE group add actor admins bcpc-$vm.$BOOTSTRAP_DOMAIN"
done


# Clustered monitoring setup (>1 mon VM) requires completely initialized node attributes for chef to run
# on each node successfully. If we are not converging automatically, set run_list (for mon VMs) and exit.
# Otherwise, each mon VM needs to complete chef run first before setting the next node's run_list.
if [[ $BOOTSTRAP_CHEF_DO_CONVERGE -eq 0 ]]; then
  for vm in $mon_vms; do
    do_on_node bootstrap "$KNIFE node run_list set bcpc-$vm.$BOOTSTRAP_DOMAIN 'role[BCPC-Monitoring]'"
  done
  echo "BOOTSTRAP_CHEF_DO_CONVERGE is set to 0, skipping automatic convergence."
  exit 0
else
  # run Chef on each node
  do_on_node bootstrap "sudo chef-client"
  for vm in $vms; do
    do_on_node $vm "sudo chef-client"
  done
  # run on head node one last time to update HAProxy with work node IPs
  do_on_node vm1 "sudo chef-client"
  # HUP OpenStack services on each node to ensure everything's in a working state
  for vm in $vms; do
    do_on_node $vm "sudo hup_openstack || true"
  done
  # Run chef on each mon VM before assigning next node for monitoring.
  for vm in $mon_vms; do
    do_on_node bootstrap "$KNIFE node run_list set bcpc-$vm.$BOOTSTRAP_DOMAIN 'role[BCPC-Monitoring]'"
    do_on_node $vm "sudo chef-client"
  done
  # Run chef on each mon VM except the last node to update cluster components
  for vm in $(echo $mon_vms | awk '{$NF=""}1'); do
    do_on_node $vm "sudo chef-client"
  done
fi
