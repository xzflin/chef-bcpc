#
# Cookbook Name:: bcpc
# Recipe:: bird
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

apt_repository "bird" do
  uri node['bcpc']['repos']['bird']
  distribution node['lsb']['codename']
  components ["main"]
  key "bird-release.key"
  notifies :run, "execute[apt-get update]", :immediately
end

package "bird" do
    action :upgrade
end

template "/etc/bird/bird.conf" do
  source "bird.conf.erb"
  mode 00644
  variables(lazy {
    {
      :servers => get_all_nodes,
      :headnodes => get_head_nodes
    }
  })
  # use get_head_nodes
  # notifies :restart, "service[bird]", :immediately
end

bash "restart-bird" do
   code "service bird restart"
end
