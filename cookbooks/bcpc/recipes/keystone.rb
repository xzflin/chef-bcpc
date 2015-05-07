#
# Cookbook Name:: bcpc
# Recipe:: keystone
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
include_recipe "bcpc::openstack"
include_recipe "bcpc::apache2"

# do not run or try to start standalone keystone service since it is now served by WSGI
service "keystone" do
  action [:disable, :stop]
end

ruby_block "initialize-keystone-config" do
    block do
        make_config('mysql-keystone-user', "keystone")
        make_config('mysql-keystone-password', secure_password)
        make_config('keystone-admin-token', secure_password)
        make_config('keystone-admin-user', "admin")
        make_config('keystone-admin-password', secure_password)
        begin
            get_config('keystone-pki-certificate')
        rescue
            temp = %x[openssl req -new -x509 -passout pass:temp_passwd -newkey rsa:2048 -out /dev/stdout -keyout /dev/stdout -days 1095 -subj "/C=#{node['bcpc']['country']}/ST=#{node['bcpc']['state']}/L=#{node['bcpc']['location']}/O=#{node['bcpc']['organization']}/OU=#{node['bcpc']['region_name']}/CN=keystone.#{node['bcpc']['domain_name']}/emailAddress=#{node['bcpc']['admin_email']}"]
            make_config('keystone-pki-private-key', %x[echo "#{temp}" | openssl rsa -passin pass:temp_passwd -out /dev/stdout])
            make_config('keystone-pki-certificate', %x[echo "#{temp}" | openssl x509])
        end

    end
end

%w{keystone memcached}.each do |pkg|
    package pkg do
        action :upgrade
    end
end

template "/etc/keystone/keystone.conf" do
    source "keystone.conf.erb"
    owner "keystone"
    group "keystone"
    mode 00600
    variables({
      :servers => get_head_nodes,
      :rabbit_hosts_shuffle_rng => Random.new(IPAddr.new(node['bcpc']['management']['ip']).to_i),
    })
    notifies :restart, "service[apache2]", :delayed
end

template "/etc/keystone/default_catalog.templates" do
    source "keystone-default_catalog.templates.erb"
    owner "keystone"
    group "keystone"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
end

template "/etc/keystone/cert.pem" do
    source "keystone-cert.pem.erb"
    owner "keystone"
    group "keystone"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
end

template "/etc/keystone/key.pem" do
    source "keystone-key.pem.erb"
    owner "keystone"
    group "keystone"
    mode 00600
    notifies :restart, "service[apache2]", :delayed
end

template "/root/adminrc" do
    source "adminrc.erb"
    owner "root"
    group "root"
    mode 00600
end

template "/root/keystonerc" do
    source "keystonerc.erb"
    owner "root"
    group "root"
    mode 00600
end

# configure WSGI

# /var/www created by apache2 package, /var/www/cgi-bin created in bcpc::apache2
wsgi_keystone_dir = "/var/www/cgi-bin/keystone"
directory wsgi_keystone_dir do
  action :create
  owner  "root"
  group  "root"
  mode   00755
end

%w{main admin}.each do |wsgi_link|
  link ::File.join(wsgi_keystone_dir, wsgi_link) do
    action :create
    to     "/usr/share/keystone/wsgi.py"
  end
end

template "/etc/apache2/sites-available/wsgi-keystone.conf" do
  source   "apache-wsgi-keystone.conf.erb"
  owner    "root"
  group    "root"
  mode     00644
  notifies :reload, "service[apache2]", :immediately
end

bash "a2ensite-enable-wsgi-keystone" do
  user     "root"
  code     "a2ensite wsgi-keystone"
  not_if   "test -r /etc/apache2/sites-enabled/wsgi-keystone.conf"
  notifies :reload, "service[apache2]", :immediately
end

ruby_block "keystone-database-creation" do
    block do
        if not system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['dbname']['keystone']}\"'|grep \"#{node['bcpc']['dbname']['keystone']}\"" then
            %x[ mysql -uroot -p#{get_config('mysql-root-password')} -e "CREATE DATABASE #{node['bcpc']['dbname']['keystone']};"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['dbname']['keystone']}.* TO '#{get_config('mysql-keystone-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-keystone-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['dbname']['keystone']}.* TO '#{get_config('mysql-keystone-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-keystone-password')}';"
                mysql -uroot -p#{get_config('mysql-root-password')} -e "FLUSH PRIVILEGES;"
            ]
            self.notifies :run, "bash[keystone-database-sync]", :immediately
            self.resolve_notification_references
        end
    end
end

bash "keystone-database-sync" do
    action :nothing
    user "root"
    code "keystone-manage db_sync"
    notifies :restart, "service[apache2]", :immediately
end

bash "keystone-create-users-tenants" do
    user "root"
    code <<-EOH
        . /root/adminrc
        . /root/keystonerc
        export KEYSTONE_ADMIN_TENANT_ID=`keystone tenant-create --name "#{node['bcpc']['admin_tenant']}" --description "Admin services" | grep " id " | awk '{print $4}'`
        export KEYSTONE_ROLE_ADMIN_ID=`keystone role-create --name "#{node['bcpc']['admin_role']}" | grep " id " | awk '{print $4}'`
        export KEYSTONE_ADMIN_LOGIN_ID=`keystone user-create --name "$OS_USERNAME" --tenant_id $KEYSTONE_ADMIN_TENANT_ID --pass "$OS_PASSWORD" --email "#{node['bcpc']['admin_email']}" --enabled true | grep " id " | awk '{print $4}'`
        keystone user-role-add --user_id $KEYSTONE_ADMIN_LOGIN_ID --role_id $KEYSTONE_ROLE_ADMIN_ID --tenant_id $KEYSTONE_ADMIN_TENANT_ID
    EOH
    only_if ". /root/keystonerc; . /root/adminrc; keystone user-get $OS_USERNAME 2>&1 | grep -e '^No user'"
end


ruby_block "initialize-keystone-test-config" do
    block do
        make_config('keystone-test-user', "tester")
        make_config('keystone-test-password', secure_password)
    end
end

ruby_block "keystone-create-test-tenants" do
    block do
        system ". /root/keystonerc; . /root/adminrc; keystone user-get #{get_config('keystone-test-user')} 2>&1 | grep -e '^No user'"
        if $?.success? then
            %x[ . /root/adminrc
                export KEYSTONE_ADMIN_TENANT_ID=`keystone tenant-get "#{node['bcpc']['admin_tenant']}" | grep " id " | awk '{print $4}'`
                keystone user-create --name #{get_config('keystone-test-user')} --tenant-id $KEYSTONE_ADMIN_TENANT_ID --pass  #{get_config('keystone-test-password')} --enabled true
            ]
        end
    end
end

ruby_block "keystone-add-test-admin-role" do
    block do
        system ". /root/keystonerc; . /root/adminrc; keystone user-role-list --user #{get_config('keystone-test-user')} --tenant '#{node['bcpc']['admin_tenant']}' 2>&1 | grep '#{node['bcpc']['admin_role']}'"
        if not $?.success? then
            %x[ . /root/adminrc
                keystone user-role-add --user #{get_config('keystone-test-user')} --role '#{node['bcpc']['admin_role']}' --tenant '#{node['bcpc']['admin_tenant']}'
            ]
        end
    end
end
