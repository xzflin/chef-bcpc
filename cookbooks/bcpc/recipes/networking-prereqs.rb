#
# Cookbook Name:: bcpc
# Recipe:: networking-prereqs
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

include_recipe "bcpc::default"
include_recipe "bcpc::system"
include_recipe "bcpc::certs"

template "/etc/hosts" do
    source "hosts.erb"
    mode 00644
    variables(:servers => get_all_nodes, :bootstrap_node => get_bootstrap_node)
end

template "/etc/ssh/sshd_config" do
    source "sshd_config.erb"
    mode 00644
    notifies :restart, "service[ssh]", :immediately
end

service "ssh" do
    action [:enable, :start]
end

service "cron" do
    action [:enable, :start]
end


# Core networking package
package "vlan"

# Enable LLDP - see https://github.com/bloomberg/chef-bcpc/pull/120
package "lldpd"

bash "enable-mellanox" do
    user "root"
    code <<-EOH
        if [ -z "`lsmod | grep mlx4_en`" ]; then
            modprobe mlx4_en
        fi
        if [ -z "`grep mlx4_en /etc/modules`" ]; then
            echo "mlx4_en" >> /etc/modules
        fi
    EOH
    only_if "lspci | grep Mellanox"
end


if node['bcpc']['enabled']['neutron']
  include_recipe 'bcpc::networking-neutron-prereqs'
else
  include_recipe 'bcpc::networking-novanetwork-prereqs'
end
