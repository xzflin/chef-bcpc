#
# Cookbook Name:: bcpc
# Recipe:: nova-head
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

include_recipe "bcpc::mysql-head"
include_recipe "bcpc::nova-common"

ruby_block "nova-database-creation" do
    block do
        %x[ export MYSQL_PWD=#{get_config('mysql-root-password')};
            mysql -uroot -e "CREATE DATABASE #{node['bcpc']['dbname']['nova']};"
            mysql -uroot -e "GRANT ALL ON #{node['bcpc']['dbname']['nova']}.* TO '#{get_config('mysql-nova-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-nova-password')}';"
            mysql -uroot -e "GRANT ALL ON #{node['bcpc']['dbname']['nova']}.* TO '#{get_config('mysql-nova-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-nova-password')}';"
            mysql -uroot -e "FLUSH PRIVILEGES;"
        ]
        self.notifies :run, "bash[nova-database-sync]", :immediately
        self.resolve_notification_references
    end
    not_if { system "MYSQL_PWD=#{get_config('mysql-root-password')} mysql -uroot -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['dbname']['nova']}\"'|grep \"#{node['bcpc']['dbname']['nova']}\" >/dev/null" }
end

# Nova API database needed by Liberty or higher
ruby_block "nova-api-database-creation" do
    block do
        %x[ export MYSQL_PWD=#{get_config('mysql-root-password')};
            mysql -uroot -e "CREATE DATABASE #{node['bcpc']['dbname']['nova_api']};"
            mysql -uroot -e "GRANT ALL ON #{node['bcpc']['dbname']['nova_api']}.* TO '#{get_config('mysql-nova-api-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-nova-api-password')}';"
            mysql -uroot -e "GRANT ALL ON #{node['bcpc']['dbname']['nova_api']}.* TO '#{get_config('mysql-nova-api-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-nova-api-password')}';"
            mysql -uroot -e "FLUSH PRIVILEGES;"
        ]
        self.notifies :run, "bash[nova-api-database-sync]", :immediately
        self.resolve_notification_references
    end
    not_if { system "MYSQL_PWD=#{get_config('mysql-root-password')} mysql -uroot -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['dbname']['nova_api']}\"'|grep \"#{node['bcpc']['dbname']['nova_api']}\" >/dev/null" }
    only_if { !is_kilo? }
end

ruby_block 'update-nova-db-schemas' do
  block do
    self.notifies :run, "bash[nova-database-sync]", :immediately
    self.notifies :run, "bash[nova-api-database-sync]", :immediately
    self.resolve_notification_references
  end
  only_if { ::File.exist?('/usr/local/etc/openstack_upgrade') }
end

bash "nova-database-sync" do
    action :nothing
    user "root"
    code "nova-manage db sync"
end

bash "nova-api-database-sync" do
    action :nothing
    user "root"
    code "nova-manage api_db sync"
end

%w{nova-scheduler nova-cert nova-consoleauth nova-conductor}.each do |pkg|
    package pkg do
        action :upgrade
    end
    service pkg do
        action [:enable, :start]
        subscribes :restart, "template[/etc/nova/nova.conf]", :delayed
        subscribes :restart, "template[/etc/nova/api-paste.ini]", :delayed
    end
end

include_recipe "bcpc::nova-work"
include_recipe "bcpc::nova-setup"
