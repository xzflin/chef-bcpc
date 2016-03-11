#
# Cookbook Name:: bcpc-foundation
# Recipe:: kernel
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
# Tools and setup useful when you're doing dev on BCPC
# but don't want them to go into a production system.
#

if node['bcpc']['kernel_version']
  ["linux-image-#{node['bcpc']['kernel_version']}",
   "linux-image-extra-#{node['bcpc']['kernel_version']}",
   "linux-headers-#{node['bcpc']['kernel_version']}",
   "linux-tools-#{node['bcpc']['kernel_version']}"].each do |pkg|
    package pkg

    bash "place-hold-on-#{pkg}" do
      code "echo #{pkg} hold | dpkg --set-selections"
      not_if "dpkg -s #{pkg} | grep ^Status: | grep -q ' hold '"
    end
  end
end

template "/etc/default/grub" do
  source "etc_default_grub.erb"
  owner  "root"
  group  "root"
  mode   00644
  notifies :run, "execute[system-update-grub]", :immediately
end

execute "system-update-grub" do
  command "update-grub"
  user "root"
  action :nothing
end
