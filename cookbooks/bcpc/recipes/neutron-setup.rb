#
# Cookbook Name:: bcpc
# Recipe:: neutron-setup
#
# Copyright 2016, Bloomberg Finance L.P.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
# http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

# this runs a block of commands to set up internal/external network for convenience
# (hardcoded IPs rather than using attributes because this was literally a copy and paste from my notes)
# because Neutron support is highly experimental, it will only run if the lock file is not in place
# to re-run the block, remove the lockfile and rechef

bash "set-up-neutron-networks" do
  code <<-EOH
    neutron net-create --router:external --provider:network_type flat --provider:physical_network ext-net1 external-network
    neutron subnet-create --allocation-pool start=192.168.100.129,end=192.168.100.254 --gateway 192.168.100.1 --disable-dhcp external-network 192.168.100.0/24
    neutron net-create --provider:network_type vxlan AdminTenant-network
    neutron subnet-create --name AdminTenant-subnet --enable-dhcp --gateway 1.127.0.1 AdminTenant-network 1.127.0.0/25
    neutron router-create AdminTenant-router
    neutron router-interface-add AdminTenant-router AdminTenant-subnet
    neutron router-gateway-set AdminTenant-router external-network
    touch /usr/local/etc/dont_recreate_neutron_networks
  EOH
  not_if { ::File.exists? '/usr/local/etc/dont_recreate_neutron_networks' }
end
