#
# Cookbook Name:: bcpc
# Provider:: osflavor
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
require 'open3'
require 'json'

def whyrun_supported?
  true
end

action :create do
  stdout, stderr, status = Open3.capture3("openstack",
                                  "--os-tenant-name", node['bcpc']['admin_tenant'], 
                                  "--os-username",  get_config('keystone-admin-user'),
                                  "--os-auth-url",  
                                  "#{node['bcpc']['protocol']['keystone']}://#{node['bcpc']['management']['vip']}:5000/v2.0/",
                                  "--os-region-name", node['bcpc']['region_name'],
                                  "--os-password" , get_config('keystone-admin-password'),
                                  "--os-cacert" , "/etc/ssl/certs/ssl-bcpc.pem",
                                  "flavor", "show", @new_resource.name , "-f", "json")
  
  if not status.success? 
    converge_by("Creating #{new_resource.name}") do
      ispub = @new_resource.is_public ? "--public" : "--private"
      stdout, status = Open3.capture2("openstack",
                                      "--os-tenant-name", node['bcpc']['admin_tenant'], 
                                      "--os-username",  get_config('keystone-admin-user'),
                                      "--os-auth-url",  
                                      "#{node['bcpc']['protocol']['keystone']}://#{node['bcpc']['management']['vip']}:5000/v2.0/",
                                      "--os-region-name", node['bcpc']['region_name'],
                                      "--os-password" , get_config('keystone-admin-password'),
                                      "--os-cacert" , "/etc/ssl/certs/ssl-bcpc.pem",
                                      "flavor", "create", @new_resource.name , "-f", "json",  
                                      "--ram=#{@new_resource.memory_mb}", 
                                      "--disk=#{@new_resource.disk_gb}",
                                      "--ephemeral=#{@new_resource.ephemeral_gb}",
                                      "--swap=#{@new_resource.swap_gb}",
                                      "--vcpus=#{@new_resource.vcpus}", 
                                      "#{ispub}"
                                      )

      if not status.success?
        Chef::Log.error "Failed to create to flavor"
      end
    end
  end   
end

action :delete do
  stdout, stderr, status = Open3.capture3("openstack",
                                          "--os-tenant-name", node['bcpc']['admin_tenant'], 
                                          "--os-username",  get_config('keystone-admin-user'),
                                          "--os-auth-url",  
                                          "#{node['bcpc']['protocol']['keystone']}://#{node['bcpc']['management']['vip']}:5000/v2.0/",
                                          "--os-region-name", node['bcpc']['region_name'],
                                          "--os-password" , get_config('keystone-admin-password'),
                                          "--os-cacert" , "/etc/ssl/certs/ssl-bcpc.pem",
                                          "flavor", "show", @new_resource.name , "-f", "json")
  if status.success? 
    converge_by("deleting #{new_resource.name}") do
      stdout, status = Open3.capture2("openstack",
                                      "--os-tenant-name", node['bcpc']['admin_tenant'], 
                                      "--os-username",  get_config('keystone-admin-user'),
                                      "--os-auth-url",  
                                      "#{node['bcpc']['protocol']['keystone']}://#{node['bcpc']['management']['vip']}:5000/v2.0/",
                                      "--os-region-name", node['bcpc']['region_name'],
                                      "--os-password" , get_config('keystone-admin-password'),
                                      "--os-cacert" , "/etc/ssl/certs/ssl-bcpc.pem",
                                      "flavor", "delete", @new_resource.name )


      if not status.success?
        Chef::Log.error "Failed to delete to flavor"
      end
    end
  end
end

