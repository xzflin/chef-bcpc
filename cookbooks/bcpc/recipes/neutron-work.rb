#
# Cookbook Name:: bcpc
# Recipe:: neutron-work
#
# Copyright 2015, Bloomberg Finance L.P.
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

include_recipe "bcpc::neutron-common"

template '/etc/neutron/plugins/ml2/ml2_conf.ini' do
  source 'neutron.ml2_conf.ini.erb'
  owner 'neutron'
  group 'neutron'
  mode 00600
end

link '/etc/neutron/plugin.ini' do
  to '/etc/neutron/plugins/ml2/ml2_conf.ini'
end

template '/etc/neutron/dhcp_agent.ini' do
  source 'neutron.dhcp_agent.ini.erb'
  owner 'neutron'
  group 'neutron'
  mode 00600
end

template '/etc/neutron/metadata_agent.ini' do
  source 'neutron.metadata_agent.ini.erb'
  owner 'neutron'
  group 'neutron'
  mode 00600
end

template '/etc/neutron/l3_agent.ini' do
  source 'neutron.l3_agent.ini.erb'
  owner 'neutron'
  group 'neutron'
  mode 00600
end

template '/etc/neutron/fwaas_driver.ini' do
  source 'neutron.fwaas_driver.ini.erb'
  owner 'neutron'
  group 'neutron'
  mode 00600
end

%w{neutron-dhcp-agent neutron-metadata-agent neutron-plugin-ml2 neutron-plugin-linuxbridge-agent neutron-l3-agent}.each do |pkg|
  package pkg do
    action :upgrade
    options "-o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"
  end
end

service 'neutron-plugin-linuxbridge-agent' do
  action [:enable, :start]
  subscribes :restart, "template[/etc/neutron/neutron.conf]", :delayed
  subscribes :restart, "template[/etc/neutron/plugins/ml2/ml2_conf.ini]", :delayed
  subscribes :restart, "template[/etc/neutron/policy.json]", :delayed
end

service 'neutron-dhcp-agent' do
  action [:enable, :start]
  subscribes :restart, "template[/etc/neutron/neutron.conf]", :delayed
  subscribes :restart, "template[/etc/neutron/dhcp_agent.ini]", :delayed
  subscribes :restart, "template[/etc/neutron/policy.json]", :delayed
end

service 'neutron-l3-agent' do
  action [:enable, :start]
  subscribes :restart, "template[/etc/neutron/neutron.conf]", :delayed
  subscribes :restart, "template[/etc/neutron/l3_agent.ini]", :delayed
  subscribes :restart, "template[/etc/neutron/fwaas_driver.ini]", :delayed
  subscribes :restart, "template[/etc/neutron/policy.json]", :delayed
end

service 'neutron-metadata-agent' do
  action [:enable, :start]
  subscribes :restart, "template[/etc/neutron/neutron.conf]", :delayed
  subscribes :restart, "template[/etc/neutron/metadata_agent.ini]", :delayed
  subscribes :restart, "template[/etc/neutron/policy.json]", :delayed
end
