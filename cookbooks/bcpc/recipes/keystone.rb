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

ruby_block "initialize-keystone-config" do
    block do
        make_config('mysql-keystone-user', "keystone")
        make_config('mysql-keystone-password', secure_password)
        make_config('keystone-admin-token', secure_password)
        make_config('keystone-admin-user',  node["bcpc"]["ldap"]["admin_user"] || "admin")
        make_config('keystone-admin-password',node["bcpc"]["ldap"]["admin_pass"]  ||  secure_password)
        begin
            get_config('keystone-pki-certificate')
        rescue
            temp = %x[openssl req -new -x509 -passout pass:temp_passwd -newkey rsa:2048 -out /dev/stdout -keyout /dev/stdout -days 1095 -subj "/C=#{node['bcpc']['country']}/ST=#{node['bcpc']['state']}/L=#{node['bcpc']['location']}/O=#{node['bcpc']['organization']}/OU=#{node['bcpc']['region_name']}/CN=keystone.#{node['bcpc']['cluster_domain']}/emailAddress=#{node['bcpc']['admin_email']}"]
            make_config('keystone-pki-private-key', %x[echo "#{temp}" | openssl rsa -passin pass:temp_passwd -out /dev/stdout])
            make_config('keystone-pki-certificate', %x[echo "#{temp}" | openssl x509])
        end

    end
end

package 'python-ldappool' do
  action :upgrade
end

package 'keystone' do
  action :upgrade
  notifies :run, 'bash[clean-old-pyc-files]', :immediately
  notifies :run, 'bash[flush-memcached]', :immediately
end

# sometimes the way tokens are stored changes and causes issues,
# so flush memcached if Keystone is upgraded
bash 'flush-memcached' do
  code "echo flush_all | nc #{node['bcpc']['management']['ip']} 11211"
  action :nothing
end

# these packages need to be updated in Liberty but are not upgraded when Keystone is upgraded
%w( python-oslo.i18n python-oslo.serialization python-pyasn1 ).each do |pkg|
  package pkg do
    action :upgrade
    notifies :restart, "service[apache2]", :immediately
    not_if { is_kilo? }
  end
end

# do not run or try to start standalone keystone service since it is now served by WSGI
service "keystone" do
    action [:disable, :stop]
end

# if on Liberty, generate Fernet keys and persist the keys in the data bag (if not already
# generated)
fernet_key_directory = '/etc/keystone/fernet-keys'

directory fernet_key_directory do
  owner 'keystone'
  group 'keystone'
  mode  00700
end

# write out keys if defined in the data bag
# (there should always be at least 0 (staged) and 1 (primary) in the data bag)
ruby_block 'write-out-fernet-keys-from-data-bag' do
  block do
    (0..2).each do |idx|
      if config_defined("keystone-fernet-key-#{idx}")
        key_path = ::File.join(fernet_key_directory, idx.to_s)
        key_in_databag = get_config("keystone-fernet-key-#{idx}")
        ::File.write(key_path, key_in_databag)
      end
    end
    # remove any other keys present in the directory (not 0, 1, or 2)
    ::Dir.glob(::File.join(fernet_key_directory, '*')).reject do |path|
      path.end_with?(*(0..2).collect(&:to_s))
    end.each do |file_to_delete|
      ::File.delete(file_to_delete)
    end
  end
  # if any key needs to be rewritten, then we'll rewrite them all
  only_if do
    need_to_write_keys = []
    (0..2).each do |idx|
      key_path = ::File.join(fernet_key_directory, idx.to_s)
      if ::File.exist?(key_path)
        key_on_disk = ::File.read(key_path)
        if config_defined("keystone-fernet-key-#{idx}")
          need_to_write_keys << (key_on_disk != get_config("keystone-fernet-key-#{idx}"))
        end
      else
        # key does not exist on disk, ensure that it is written out
        need_to_write_keys << true
      end
    end
    need_to_write_keys.any?
  end
  notifies :restart, 'service[apache2]', :immediately
end

# generate Fernet keys if there are not any on disk (first time setup)
ruby_block 'first-time-fernet-key-generation' do
  block do
    Mixlib::ShellOut.new('keystone-manage fernet_setup --keystone-user keystone --keystone-group keystone').run_command.error!
    make_config('keystone-fernet-last-rotation', Time.now)
  end
  not_if { ::File.exist?(::File.join(fernet_key_directory, '0')) }
  notifies :restart, 'service[apache2]', :immediately
end

# if the staged key's mtime is at least this many days old and the data bag
# has recorded a last rotation timestamp , execute a rotation
ruby_block 'rotate-fernet-keys' do
  block do
    fernet_keys = ::Dir.glob(::File.join(fernet_key_directory, '*')).sort

    # the current staged key (0) will become the new master
    new_master_key = ::File.read(fernet_keys.first)
    # the current master key (highest index) will become a secondary key
    old_master_key = ::File.read(fernet_keys.last)
    # execute a rotation via keystone-manage so that we get a new staging key
    Mixlib::ShellOut.new('keystone-manage fernet_rotate --keystone-user keystone --keystone-group keystone').run_command.error!
    # 0 is now the new staging key so read that file again
    new_staging_key = ::File.read(fernet_keys.first)

    # destroy the on-disk keys before we rewrite them to disk
    ::Dir.glob(::File.join(fernet_key_directory, '*')).each do |fk|
      ::File.delete(fk)
    end

    # write new master key to 2
    ::File.write(::File.join(fernet_key_directory, '2'), new_master_key)
    # write staging key to 0
    ::File.write(::File.join(fernet_key_directory, '0'), new_staging_key)
    # write old master key to 1
    ::File.write(::File.join(fernet_key_directory, '1'), old_master_key)

    # re-permission all keys to ensure they are owned by keystone and chmod 600
    Mixlib::ShellOut.new('chown keystone:keystone /etc/keystone/fernet-keys/*').run_command.error!
    Mixlib::ShellOut.new('chmod 0600 /etc/keystone/fernet-keys/*').run_command.error!

    # update keystone-fernet-last-rotation timestamp
    make_config('keystone-fernet-last-rotation', Time.now.to_i, force=true)

    # (writing these keys into the data bag will be done by the add-fernet-keys-to-data-bag resource)
  end
  only_if do
    # if key rotation is disabled then skip out
    if node['bcpc']['keystone']['rotate_fernet_tokens']
      if config_defined('keystone-fernet-last-rotation')
        Time.now.to_i - get_config('keystone-fernet-last-rotation').to_i > node['bcpc']['keystone']['fernet_token_max_age_seconds']
      else
        # always run if keystone-fernet-last-rotation is not defined
        # (upgrade from 6.0.0)
        true
      end
    else
      false
    end
  end
  notifies :restart, 'service[apache2]', :immediately
end

# key indexes in the data bag will not necessarily match the files on disk
# (staged key is always key 0, primary key is the highest-indexed one, any
# keys in between are former primary keys that can only decrypt)
ruby_block 'add-fernet-keys-to-data-bag' do
  block do
    fernet_keys = ::Dir.glob(::File.join(fernet_key_directory, '*')).sort
    fernet_keys.each_with_index do |key_path, idx|
      db_key = "keystone-fernet-key-#{idx}"
      disk_key_value = ::File.read(key_path)
      begin
        db_key_value = get_config(db_key)
        make_config(db_key, disk_key_value, force=true) unless db_key_value == disk_key_value
        # save old key to backup slot Just In Case
        make_config("#{db_key}-backup", db_key_value, force=true)
      rescue
        make_config(db_key, disk_key_value)
      end
    end
  end
  only_if do
    need_to_add_keys = []
    (0..2).each do |idx|
      key_path = ::File.join(fernet_key_directory, idx.to_s)
      if ::File.exist?(key_path)
        key_on_disk = ::File.read(key_path)
        if config_defined("keystone-fernet-key-#{idx}")
          need_to_add_keys << (key_on_disk != get_config("keystone-fernet-key-#{idx}"))
        else
          need_to_add_keys << true
        end
      end
    end
    need_to_add_keys.any?
  end
end

# standalone Keystone service has a window to start up in and create keystone.log with
# wrong permissions, so ensure it's owned by keystone:keystone
file "/var/log/keystone/keystone.log" do
  owner "keystone"
  group "keystone"
  notifies :restart, "service[apache2]", :immediately
end

template "/etc/keystone/keystone.conf" do
    source "keystone.conf.erb"
    owner "keystone"
    group "keystone"
    mode 00600
    variables(:servers => get_head_nodes)
    notifies :restart, "service[apache2]", :immediately
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

template "/etc/keystone/policy.json" do
    source "keystone-policy.json.erb"
    owner "keystone"
    group "keystone"
    mode 00600
    variables(:policy => JSON.pretty_generate(node['bcpc']['keystone']['policy']))
end

template "/root/adminrc" do
    source "adminrc.erb"
    owner "root"
    group "root"
    mode 00600
end

template "/root/api_versionsrc" do
    source "api_versionsrc.erb"
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
  variables(
    :processes => node['bcpc']['keystone']['wsgi']['processes'],
    :threads   => node['bcpc']['keystone']['wsgi']['threads']
  )
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
        %x[ export MYSQL_PWD=#{get_config('mysql-root-password')};
            mysql -uroot -e "CREATE DATABASE #{node['bcpc']['dbname']['keystone']};"
            mysql -uroot -e "GRANT ALL ON #{node['bcpc']['dbname']['keystone']}.* TO '#{get_config('mysql-keystone-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-keystone-password')}';"
            mysql -uroot -e "GRANT ALL ON #{node['bcpc']['dbname']['keystone']}.* TO '#{get_config('mysql-keystone-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-keystone-password')}';"
            mysql -uroot -e "FLUSH PRIVILEGES;"
        ]
        self.notifies :run, "bash[keystone-database-sync]", :immediately
        self.resolve_notification_references
    end
    not_if { system "MYSQL_PWD=#{get_config('mysql-root-password')} mysql -uroot -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['dbname']['keystone']}\"'|grep \"#{node['bcpc']['dbname']['keystone']}\" >/dev/null" }
end

ruby_block 'update-keystone-db-schema' do
  block do
    self.notifies :run, "bash[keystone-database-sync]", :immediately
    self.resolve_notification_references
  end
  only_if { ::File.exist?('/usr/local/etc/openstack_upgrade') }
end

bash "keystone-database-sync" do
    action :nothing
    user "root"
    code "keystone-manage db_sync"
    notifies :restart, "service[apache2]", :immediately
end

ruby_block "keystone-region-creation" do
    block do
        %x[ export MYSQL_PWD=#{get_config('mysql-root-password')};
            mysql -uroot -e "INSERT INTO keystone.region (id, extra) VALUES(\'#{node['bcpc']['region_name']}\', '{}');"
        ]
    end
    not_if { system "MYSQL_PWD=#{get_config('mysql-root-password')} mysql -uroot -e 'SELECT id FROM keystone.region WHERE id = \"#{node['bcpc']['region_name']}\"' | grep \"#{node['bcpc']['region_name']}\" >/dev/null" }
end

# this is a synchronization resource that polls Keystone on the VIP to verify that it's not returning 503s,
# if something above has restarted Apache and Keystone isn't ready to play yet
bash "wait-for-keystone-to-become-operational" do
  code ". /root/keystonerc; until keystone user-list >/dev/null 2>&1; do sleep 1; done"
  timeout node['bcpc']['keystone']['wait_for_keystone_timeout']
end

bash "keystone-create-admin-user" do
    user "root"
    code <<-EOH
        . /root/adminrc
        . /root/keystonerc
       keystone user-create --name "$OS_USERNAME" --pass "$OS_PASSWORD"  --enabled true
    EOH
    not_if ". /root/keystonerc; . /root/adminrc; keystone user-get $OS_USERNAME"
end

bash "keystone-create-admin-tenant" do
    user "root"
    code <<-EOH
        . /root/adminrc
        . /root/keystonerc
        keystone tenant-create --name "#{node['bcpc']['admin_tenant']}" --description "Admin services"
    EOH
    not_if ". /root/keystonerc; . /root/adminrc; keystone tenant-get '#{node['bcpc']['admin_tenant']}'"
end

bash "keystone-create-admin-role" do
    user "root"
    code <<-EOH
        . /root/adminrc
        . /root/keystonerc
        keystone role-create --name "#{node['bcpc']['admin_role']}"
    EOH
    not_if ". /root/keystonerc; . /root/adminrc; keystone role-get '#{node['bcpc']['admin_role']}'"
end


bash "keystone-create-member-role" do
    user "root"
    code <<-EOH
        . /root/adminrc
        . /root/keystonerc
        keystone role-create --name "#{node['bcpc']['member_role']}"
    EOH
    not_if ". /root/keystonerc; . /root/adminrc; keystone role-get '#{node['bcpc']['member_role']}'"
end


bash "keystone-create-admin-user-role" do
    user "root"
    code <<-EOH
        . /root/adminrc
        . /root/keystonerc
        keystone user-role-add --user  "$OS_USERNAME"  --role "#{node['bcpc']['admin_role']}" --tenant "#{node['bcpc']['admin_tenant']}"
    EOH
    not_if ". /root/keystonerc; . /root/adminrc; keystone user-role-list --user  $OS_USERNAME  --tenant '#{node['bcpc']['admin_tenant']}'   | grep '#{node['bcpc']['admin_role']}'"
end

# create services and endpoints
node['bcpc']['catalog'].each do |svc, svcprops|
  # attempt to delete endpoints that no longer match the environment
  # (keys off the service type, so it is possible to orphan endpoints if you remove an
  # entry from the environment service catalog)
  ruby_block "keystone-delete-outdated-#{svc}-endpoint" do
    block do
      svc_endpoints_raw = execute_in_keystone_admin_context('openstack endpoint list -f json')
      begin
        #puts svc_endpoints_raw
        svc_endpoints = JSON.parse(svc_endpoints_raw)
        #puts svc_endpoints
        svc_ids = svc_endpoints.select { |k| k['Service Type'] == svc }.collect { |v| v['ID'] }
        #puts svc_ids
        svc_ids.each do |svc_id|
          execute_in_keystone_admin_context("openstack endpoint delete #{svc_id} 2>&1")
        end
      rescue JSON::ParserError
      end
    end
    not_if {
      #puts 'starting not_if block'
      svc_endpoints_raw = execute_in_keystone_admin_context('openstack endpoint list -f json')
      begin
        #puts "\nsvc_endpoints_raw: #{svc_endpoints_raw}"
        svc_endpoints = JSON.parse(svc_endpoints_raw)
        #puts "\nsvc_endpoints: #{svc_endpoints}"
        next if svc_endpoints.empty?
        # get the endpoint ID here
        svcs = svc_endpoints.select { |k| k['Service Type'] == svc }
        #puts "\nsvcs: #{svcs}"
        next if svcs.empty?

        # openstack endpoint list output completely changes between Kilo and Liberty, because OpenStack
        if is_kilo?
          endpoint_id = svcs[0]['ID']
          #puts "\n#{endpoint_id}"
          endpoint_urls_raw = execute_in_keystone_admin_context("openstack endpoint show #{endpoint_id} -f json")
          endpoint_urls = JSON.parse(endpoint_urls_raw)
          #puts "\nendpoint_urls: #{endpoint_urls}"

          # nil is a dodge to avoid issues when standing a service up during a fresh install
          adminurl_raw = endpoint_urls.select { |v| v if v['Field'] == 'adminurl' } || nil
          adminurl = adminurl_raw.empty? ? nil : adminurl_raw[0]['Value']
          internalurl_raw = endpoint_urls.select { |v| v if v['Field'] == 'internalurl' } || nil
          internalurl = internalurl_raw.empty? ? nil : internalurl_raw[0]['Value']
          publicurl_raw = endpoint_urls.select { |v| v if v['Field'] == 'publicurl' } || nil
          publicurl = publicurl_raw.empty? ? nil : publicurl_raw[0]['Value']
        else
          adminurl_raw = svcs.select { |v| v['URL'] if v['Interface'] == 'admin' }
          adminurl = adminurl_raw.empty? ? nil : adminurl_raw[0]['URL']
          internalurl_raw = svcs.select { |v| v['URL'] if v['Interface'] == 'internal' }
          internalurl = internalurl_raw.empty? ? nil : internalurl_raw[0]['URL']
          publicurl_raw = svcs.select { |v| v['URL'] if v['Interface'] == 'public' }
          publicurl = publicurl_raw.empty? ? nil : publicurl_raw[0]['URL']
        end

        #puts "\n"
        #puts "Comparing #{adminurl} to #{generate_service_catalog_uri(svcprops, 'admin')}"
        #puts "Comparing #{internalurl} to #{generate_service_catalog_uri(svcprops, 'internal')}"
        #puts "Comparing #{publicurl} to #{generate_service_catalog_uri(svcprops, 'public')}"

        adminurl_match = adminurl.nil? ? true : (adminurl == generate_service_catalog_uri(svcprops, 'admin'))
        internalurl_match = internalurl.nil? ? true : (internalurl == generate_service_catalog_uri(svcprops, 'internal'))
        publicurl_match = publicurl.nil? ? true : (publicurl == generate_service_catalog_uri(svcprops, 'public'))

        #puts 'ending not_if block successfully'

        adminurl_match && internalurl_match && publicurl_match
      rescue JSON::ParserError
        #puts 'failing out of not_if block'
        false
      end
    }
  end

  # why no corresponding deletion for out of date services?
  # services don't get outdated in the way endpoints do (since endpoints encode version numbers and ports),
  # services just say that service X is present in the catalog, not how to access it

  ruby_block "keystone-create-#{svc}-service" do
    block do
      execute_in_keystone_admin_context("openstack service create --name '#{svcprops['name']}' --description '#{svcprops['description']}' #{svc}")
    end
    only_if {
      services_raw = execute_in_keystone_admin_context('openstack service list -f json')
      services = JSON.parse(services_raw)
      services.select { |s| s['Type'] == svc }.length.zero?
    }
  end

  # openstack command syntax changes between identity API v2 and v3, so calculate the endpoint creation command ahead of time
  identity_api_version = node['bcpc']['catalog']['identity']['uris']['public'].scan(/^[^\d]*(\d+)/)[0][0].to_i
  if identity_api_version == 3
    endpoint_create_cmd = <<-EOH
      openstack endpoint create \
          --region '#{node['bcpc']['region_name']}' #{svc} public "#{generate_service_catalog_uri(svcprops, 'public')}" ;
      openstack endpoint create \
          --region '#{node['bcpc']['region_name']}' #{svc} internal "#{generate_service_catalog_uri(svcprops, 'internal')}" ;
      openstack endpoint create \
          --region '#{node['bcpc']['region_name']}' #{svc} admin "#{generate_service_catalog_uri(svcprops, 'admin')}" ;
    EOH
  else
    endpoint_create_cmd = <<-EOH
      openstack endpoint create \
          --region '#{node['bcpc']['region_name']}' \
          --publicurl "#{generate_service_catalog_uri(svcprops, 'public')}" \
          --adminurl "#{generate_service_catalog_uri(svcprops, 'admin')}" \
          --internalurl "#{generate_service_catalog_uri(svcprops, 'internal')}" \
          #{svc}
    EOH
  end

  ruby_block "keystone-create-#{svc}-endpoint" do
    block do
      execute_in_keystone_admin_context(endpoint_create_cmd)
    end
    only_if {
      endpoints_raw = execute_in_keystone_admin_context('openstack endpoint list -f json')
      endpoints = JSON.parse(endpoints_raw)
      endpoints.select { |e| e['Service Type'] == svc }.length.zero?
    }
  end
end
