#!/bin/bash

#
# This script expects to be run in the chef-bcpc directory with root under sudo
#

set -e

if [[ -f ./proxy_setup.sh ]]; then
  . ./proxy_setup.sh
fi

if [[ -z "$1" ]]; then
        BOOTSTRAP_IP=10.0.100.3
else
        BOOTSTRAP_IP=$1
fi

# needed within build_bins which we call
if [[ -z "$CURL" ]]; then
	echo "CURL is not defined"
	exit
fi

if dpkg -s chef-server-core 2>/dev/null | grep -q Status.*installed; then
  echo chef server is installed
else
  dpkg -i cookbooks/bcpc/files/default/bins/chef-server.deb
  if [ ! -f /etc/opscode/chef-server.rb ]; then
    if [ ! -d /etc/opscode ]; then
      mkdir /etc/opscode
      chown 775 /etc/opscode
    fi
    cat > /etc/opscode/chef-server.rb <<EOF
api_fqdn "${BOOTSTRAP_IP}"
# allow connecting to http port directly
nginx['enable_non_ssl'] = true
# have nginx listen on port 4000
nginx['non_ssl_port'] = 4000
# allow long-running recipes not to die with an error due to auth
#opscode_erchef['s3_url_ttl'] = 3600
EOF
  fi
  chef-server-ctl reconfigure
  chef-server-ctl user-create admin admin admin admin@localhost.com welcome --filename /etc/opscode/admin.pem
  chef-server-ctl org-create bcpc "BCPC" --association admin --filename /etc/opscode/bcpc-validator.pem
  chmod 0600 /etc/opscode/{bcpc-validator,admin}.pem
fi

dpkg -E -i cookbooks/bcpc/files/default/bins/chef-client.deb

if [[ -n "$SUDO_USER" ]]; then
  OWNER=$SUDO_USER
else
  OWNER=$USER
fi

install -d -m0770 -o $OWNER .chef
install -m0600 -o $OWNER /etc/opscode/admin.pem .chef/admin.pem
install -m0600 -o $OWNER /etc/opscode/bcpc-validator.pem .chef/bcpc-validator.pem

# copy our ssh-key to be authorized for root
if [[ -f $HOME/.ssh/authorized_keys && ! -f /root/.ssh/authorized_keys ]]; then
  if [[ ! -d /root/.ssh ]]; then
    mkdir /root/.ssh
  fi
  cp $HOME/.ssh/authorized_keys /root/.ssh/authorized_keys
fi
