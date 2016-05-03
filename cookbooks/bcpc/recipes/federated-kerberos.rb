#
# Cookbook Name:: bcpc
# Recipe:: federated-kerberos
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
    
# install the apache mod
package "libapache2-mod-auth-kerb" do
    action :upgrade
end

# drop the sso template into place
# TODo: Should attempt to clone/download file first from upstream
cookbook_file "/etc/keystone/sso_callback_template.html" do
    owner "root"
    group "root"
    mode "0644"
    source "keystone/sso_callback_template.html"
end

# drop the mapping template into place
template "Chef::Config['file_cache_path']/kerberos-mapping.json" do
    owner "root"
    group "root"
    mode "0644"
    source "keystone/kerberos-mapping.json.erb"
    variables :group_id => node['bcpc']['keystone']['federation']['kerberos']['users_group']
end

## do the keystsone wsgi bits
#chef_gem "chef-rewind"
#require "chef/rewind"

include_recipe "bcpc::keystone"

# Do keystone setup
bash "keystone-create-kerberos-users-group" do
    user "root"
    code <<-EOH
        . /root/adminrc
#        . /root/keystonerc
        openstack group create #{node['bcpc']['keystone']['federation']['kerberos']['users_group']}
    EOH
    not_if ". /root/adminrc; openstack group show #{node['bcpc']['keystone']['federation']['kerberos']['users_group']}"
end

bash "keystone-create-kerberos-users-group-mapping" do
    user "root"
    code <<-EOH
        . /root/adminrc
        openstack role add --project AdminTenant --group #{node['bcpc']['keystone']['federation']['kerberos']['users_group']} Member
    EOH
    not_if ". /root/adminrc; openstack role assignment list --group-domain Default --group #{node['bcpc']['keystone']['federation']['kerberos']['users_group']} --project AdminTenant"
end

bash "keystone-create-kerberos-identity-provider" do
    user "root"
    code <<-EOH
        . /root/adminrc
        openstack identity provider create --description Kerberos --remote-id #{node['bcpc']['keystone']['federation']['kerberos']['remote_id']} #{node['bcpc']['keystone']['federation']['kerberos']['provider_name']}
    EOH
    not_if ". /root/adminrc; openstack identity provider show #{node['bcpc']['keystone']['federation']['kerberos']['provider_name']}"
end

bash "keystone-create-kerberos-identity-mapping" do
    user "root"
    code <<-EOH
        . /root/adminrc
        openstack mapping create --rules #{Chef::Config['file_cache_path']/kerberos-mapping.json} #{node['bcpc']['keystone']['federation']['kerberos']['mapping_name']}
    EOH
    not_if ". /root/adminrc; openstack mapping show #{node['bcpc']['keystone']['federation']['kerberos']['mapping_name']}"
end

bash "keystone-create-kerberos-federation-protocol" do
    user "root"
    code <<-EOH
        . /root/adminrc
        openstack federation protocol create --identity-provider #{node['bcpc']['keystone']['federation']['kerberos']['provider_name']}" --mapping #{node['bcpc']['keystone']['federation']['kerberos']['mapping_name']} #{node['bcpc']['keystone']['federation']['kerberos']['protocol_name']}
    EOH
    not_if ". /root/adminrc; openstack federation protocol show --identity-provider #{node['bcpc']['keystone']['federation']['kerberos']['provider_name']} #{node['bcpc']['keystone']['federation']['kerberos']['protocol_name']}"
end
#openstack identity provider set --remote-id KERB_ID kerb
