#
# Cookbook Name:: bcpc
# Recipe:: nova-setup
#
# Copyright 2013, Bloomberg Finance L.P.
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

include_recipe "bcpc::keystone"
include_recipe "bcpc::nova-head"

#  _   _  ____ _  __   __  ____   _  _____ ____ _   _
# | | | |/ ___| | \ \ / / |  _ \ / \|_   _/ ___| | | |
# | | | | |  _| |  \ V /  | |_) / _ \ | || |   | |_| |
# | |_| | |_| | |___| |   |  __/ ___ \| || |___|  _  |
#  \___/ \____|_____|_|   |_| /_/   \_\_| \____|_| |_|
# this patch resolves OpenStack issue #1456321 and BCPC issue #573 -
# fixes DHCP server assignment so that each fixed IP subnet gets its gateway
# address as its DHCP server by default instead of all subnets getting the
# gateway of the lowest subnet
cookbook_file "/tmp/nova-network-dhcp-server.patch" do
    source "nova-network-dhcp-server.patch"
    owner "root"
    mode 00644
end

bash "patch-for-nova-network-dhcp-server" do
    user "root"
    code <<-EOH
       cd /usr/lib/python2.7/dist-packages
       patch -p1 < /tmp/nova-network-dhcp-server.patch
       rv=$?
       if [ $rv -ne 0 ]; then
         echo "Error applying patch ($rv) - aborting!"
         exit $rv
       fi
       cp /tmp/nova-network-dhcp-server.patch .
    EOH
    not_if "test -f /usr/lib/python2.7/dist-packages/nova-network-dhcp-server.patch"
    notifies :restart, "service[nova-api]", :immediately
end

bash "nova-default-secgroup" do
    user "root"
    code <<-EOH
        . /root/adminrc
        nova secgroup-add-rule default icmp -1 -1 0.0.0.0/0
        nova secgroup-add-rule default tcp 22 22 0.0.0.0/0
    EOH
    not_if ". /root/adminrc; nova secgroup-list-rules default | grep icmp"
end

bash "nova-floating-add" do
    user "root"
    code <<-EOH
        . /root/adminrc
        nova-manage floating create --ip_range=#{node['bcpc']['floating']['available_subnet']} --pool #{node['bcpc']['region_name']}
    EOH
    only_if ". /root/adminrc; nova-manage floating list | grep \"No floating IP addresses have been defined\""
end

bash "nova-fixed-add" do
    user "root"
    code <<-EOH
        . /root/adminrc
        nova-manage network create --label fixed --fixed_range_v4=#{node['bcpc']['fixed']['cidr']} --num_networks=#{node['bcpc']['fixed']['num_networks']} --multi_host=T --network_size=#{node['bcpc']['fixed']['network_size']} --vlan_start=#{node['bcpc']['fixed']['vlan_start']} --bridge_interface=#{node['bcpc']['fixed']['vlan_interface']}
    EOH
    only_if ". /root/adminrc; nova-manage network list | grep \"No networks found\""
end
