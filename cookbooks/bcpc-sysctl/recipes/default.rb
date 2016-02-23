#
# Cookbook Name:: bcpc-sysctl
# Recipe:: default
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

package "conntrack" do
  action :upgrade
end

bash "load-nf_conntrack-module" do
  code "modprobe nf_conntrack"
  not_if "lsmod | grep -q '^nf_conntrack\s'"
end

template "/etc/sysctl.d/70-bcpc.conf" do
  source "sysctl-70-bcpc.conf.erb"
  owner "root"
  group "root"
  mode 00644
  variables(
    :additional_reserved_ports => node['bcpc']['system']['additional_reserved_ports'],
    :parameters => node['bcpc']['system']['parameters']
  )
  notifies :run, "execute[reload-sysctl]", :immediately
end

execute "reload-sysctl" do
  action :nothing
  command "sysctl --system"
end

ruby_block "set-nf_conntrack-hashsize" do
  block do
    %x[ echo $((#{node['bcpc']['system']['parameters']['net.nf_conntrack_max']}/8)) > /sys/module/nf_conntrack/parameters/hashsize ]
  end
  not_if { system "grep -q ^$((#{node['bcpc']['system']['parameters']['net.nf_conntrack_max']}/8))$ /sys/module/nf_conntrack/parameters/hashsize" }
end
