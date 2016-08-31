#
# Cookbook Name:: bcpc
# Recipe:: pacemaker
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


# hack. will be moved to common firewall definitions later
bash "iptables-for-corosync" do
    user "root"
    code <<-EOH
        iptables -A INPUT  -i eth1 -p udp -m multiport --dports 5404,5405,5406 -m conntrack --ctstate NEW,ESTABLISHED -j ACCEPT
        iptables -A OUTPUT  -o eth1 -p udp -m multiport --sports 5404,5405,5406 -m conntrack --ctstate ESTABLISHED -j ACCEPT
    EOH
end

# copied from keepalived
# those kick pdns and openstack services on vip change
%w{if_vip if_not_vip vip_change}.each do |script|
    template "/usr/local/bin/#{script}" do
        source "keepalived-#{script}.erb"
        mode 0755
        owner "root"
        group "root"
    end
end

%w{vip_won vip_lost}.each do |symlink|
    link "/usr/local/bin/#{symlink}" do
        to "/usr/local/bin/vip_change"
        mode 0755
        owner "root"
        group "root"
    end
end


# this will install corosync, libqb0, crmsh dependencies
package "pacemaker" do
    action :upgrade
end

# allow corosync to automatically start
template '/etc/default/corosync' do
  source 'corosync.erb'
  mode 00644
end

# corosync.conf
template '/etc/corosync/corosync.conf' do
  source 'corosync.conf.erb'
  mode 00644
  variables(:headnodes => get_head_nodes)
  notifies :restart, "service[corosync]", :immediately
end

service "corosync" do
    action [:enable, :start]
end

# enable pacemaker autostart (after corosync)
bash "make-pacemaker-autostart" do
    user "root"
    code "update-rc.d pacemaker defaults 20 01"
end

# TODO: add guard for corosync start\convergence

# start pacemaker
service "pacemaker" do
    action [:enable, :start]
end

# modified Dummy resource to run vip_{won,lost} on vip migration.
# will be removed when pacemaker\crmsh version will be updated
cookbook_file "/usr/lib/ocf/resource.d/heartbeat/Osr" do
  source "Openstack_reload"
  owner "root"
  mode 00755
end

# cluster resources definition
template "/tmp/pacemaker.conf" do
    source "pacemaker.conf.erb"
end

# TODO: replace with proper guard
bash "wait-for-pacemaker" do
    user "root"
    code "sleep 20"
end

bash "disable-stonith" do
    user "root"
    code "crm configure property stonith-enabled=false"
end

# check if we are first headnode being deployed
# if we are not, no need to load resources
bash "load-cluster-resources" do
    user "root"
    code "crm configure load replace /tmp/pacemaker.conf"
end
