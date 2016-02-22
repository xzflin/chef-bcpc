#
# Cookbook Name:: bcpc
# Recipe:: calico-head
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

# include_recipe "bird" instead of explicit inclusion in run-list???

apt_repository "calico" do
  uri node['bcpc']['repos']['calico']
  distribution node['lsb']['codename']
  components ["main"]
  key "calico-release.key"
  notifies :run, "execute[apt-get update]", :immediately
end

# install etcd (this comes from calico repo!)
package "etcd" do
    action :upgrade
end

package "python-etcd" do
    action :upgrade
end

# stop etcd while we create a tmpfs datadir and write proper config
service "etcd" do
    action [:enable, :stop]
end

# TODO: HACK
bash "etcd-data-dir" do
  user 'root'
  code <<-EOH
       service etcd stop
       sleep 5
       rm -rf /var/lib/etcd/*
       mount -t tmpfs -o size=512m tmpfs /var/lib/etcd
       egrep '^tmpfs /var/lib/etcd' /etc/fstab || echo 'tmpfs /var/lib/etcd tmpfs nodev,nosuid,noexec,nodiratime,size=512M 0 0' >> /etc/fstab
  EOH
  # not_if "grep '/var/lib/etcd' /etc/fstab"
end

# /etc/init/etcd.conf
# pass head_nodes => get_head_nodes
# and check for node['hostname']
template "/etc/init/etcd.conf" do
    source "etcd.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :start, "service[etcd]", :immediately
end

service "etcd" do
    action [:enable, :start]
end

bash "upgrade-dnsmasq" do
    code "apt-get install -y --only-upgrade dnsmasq-base"
end

bash "upgrade-dnsmasq-utils" do
    code "apt-get install -y --only-upgrade dnsmasq-utils"
end

package "calico-control" do
    action :upgrade
end

# sudo  service neutron-server restart
bash "restart-neutron-server" do
  code "service neutron-server restart"
end
