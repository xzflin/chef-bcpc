#
# Cookbook Name:: bcpc
# Recipe:: horizon
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

ruby_block "initialize-horizon-config" do
    block do
        make_config('mysql-horizon-user', "horizon")
        make_config('mysql-horizon-password', secure_password)
        make_config('horizon-secret-key', secure_password)
    end
end

# this resource exists as a little trick to ensure the upgrade goes
# smoothly even if the dashboard Apache configuration is in the old
# place that blows up the postinst script
file "/etc/apache2/conf-available/openstack-dashboard.conf" do
  action :create_if_missing
end

# options specified to keep dpkg from complaining that the config file exists already
package "openstack-dashboard" do
  action :upgrade
  options "-o Dpkg::Options::='--force-confdef' -o Dpkg::Options::='--force-confold'"
  notifies :run, "bash[dpkg-reconfigure-openstack-dashboard]", :delayed
end

#  _   _  ____ _  __   __  ____   _  _____ ____ _   _
# | | | |/ ___| | \ \ / / |  _ \ / \|_   _/ ___| | | |
# | | | | |  _| |  \ V /  | |_) / _ \ | || |   | |_| |
# | |_| | |_| | |___| |   |  __/ ___ \| || |___|  _  |
#  \___/ \____|_____|_|   |_| /_/   \_\_| \____|_| |_|

# this patch explicitly sets the Content-Length header when uploading files into
# containers via Horizon (not upstreamed) - not needed for 2015.1.4 and beyond
bcpc_patch 'horizon-swift-content-length-kilo' do
  patch_file           'horizon-swift-content-length.patch'
  patch_root_dir       '/usr/share/openstack-dashboard'
  shasums_before_apply 'horizon-swift-content-length-kilo-BEFORE.SHASUMS'
  shasums_after_apply  'horizon-swift-content-length-kilo-AFTER.SHASUMS'
  notifies :restart, 'service[apache2]', :delayed
  only_if "dpkg --compare-versions $(dpkg -s openstack-dashboard | egrep '^Version:' | awk '{ print $NF }') ge 1:2015.1.0 && dpkg --compare-versions $(dpkg -s openstack-dashboard | egrep '^Version:' | awk '{ print $NF }') lt 1:2015.1.4"
end

bcpc_patch 'horizon-swift-content-length-liberty' do
  patch_file           'horizon-swift-content-length.patch'
  patch_root_dir       '/usr/share/openstack-dashboard'
  shasums_before_apply 'horizon-swift-content-length-liberty-BEFORE.SHASUMS'
  shasums_after_apply  'horizon-swift-content-length-liberty-AFTER.SHASUMS'
  notifies :restart, 'service[apache2]', :delayed
  only_if "dpkg --compare-versions $(dpkg -s openstack-dashboard | egrep '^Version:' | awk '{ print $NF }') ge 2:0"
end

# this adds a way to override and customize Horizon's behavior
horizon_customize_dir = ::File.join('/', 'usr', 'local', 'bcpc-horizon', 'bcpc')
directory horizon_customize_dir do
  action    :create
  recursive true
end

file ::File.join(horizon_customize_dir, '__init__.py') do
  action :create
end

template ::File.join(horizon_customize_dir, 'overrides.py') do
  source   'horizon.overrides.py.erb'
  notifies :restart, "service[apache2]", :delayed
end

package "openstack-dashboard-ubuntu-theme" do
    action :remove
    notifies :run, "bash[dpkg-reconfigure-openstack-dashboard]", :delayed
end

template "/etc/apache2/conf-available/openstack-dashboard.conf" do
    source "apache-openstack-dashboard.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
    notifies :run, "bash[dpkg-reconfigure-openstack-dashboard]", :delayed
end

# we used to remove the Horizon config from conf-* and move it to sites-*
# but this broke the package postinst, so it is now moved back and
# these resources clean it up
file "/etc/apache2/sites-enabled/openstack-dashboard.conf" do
  action :delete
  notifies :restart, "service[apache2]", :delayed
end

file "/etc/apache2/sites-available/openstack-dashboard.conf" do
  action :delete
  notifies :restart, "service[apache2]", :delayed
end

bash "apache-enable-openstack-dashboard" do
    user "root"
    code "a2enconf openstack-dashboard"
    not_if "test -r /etc/apache2/conf-enabled/openstack-dashboard.conf"
    notifies :restart, "service[apache2]", :delayed
end

template "/etc/openstack-dashboard/local_settings.py" do
    source "horizon.local_settings.py.erb"
    owner "root"
    group "root"
    mode 00644
    variables(:servers => get_head_nodes)
    notifies :restart, "service[apache2]", :delayed
end

template "/usr/share/openstack-dashboard/openstack_dashboard/conf/cinder_policy.json" do
    source "cinder-policy.json.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
    variables(:policy => JSON.pretty_generate(node['bcpc']['cinder']['policy']))
end

template "/usr/share/openstack-dashboard/openstack_dashboard/conf/glance_policy.json" do
    source "glance-policy.json.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
    variables(:policy => JSON.pretty_generate(node['bcpc']['glance']['policy']))
end

template "/usr/share/openstack-dashboard/openstack_dashboard/conf/heat_policy.json" do
    source "heat-policy.json.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
    variables(:policy => JSON.pretty_generate(node['bcpc']['heat']['policy']))
end

template "/usr/share/openstack-dashboard/openstack_dashboard/conf/keystone_policy.json" do
    source "keystone-policy.json.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
    variables(:policy => JSON.pretty_generate(node['bcpc']['keystone']['policy']))
end

template "/usr/share/openstack-dashboard/openstack_dashboard/conf/nova_policy.json" do
    source "nova-policy.json.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[apache2]", :delayed
    variables(:policy => JSON.pretty_generate(node['bcpc']['nova']['policy']))
end

# Horizon does not have a database in Liberty
if is_kilo?
  ruby_block "horizon-database-creation" do
      block do
          %x[ export MYSQL_PWD=#{get_config('mysql-root-password')};
              mysql -uroot -e "CREATE DATABASE #{node['bcpc']['dbname']['horizon']};"
              mysql -uroot -e "GRANT ALL ON #{node['bcpc']['dbname']['horizon']}.* TO '#{get_config('mysql-horizon-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-horizon-password')}';"
              mysql -uroot -e "GRANT ALL ON #{node['bcpc']['dbname']['horizon']}.* TO '#{get_config('mysql-horizon-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-horizon-password')}';"
              mysql -uroot -e "FLUSH PRIVILEGES;"
          ]
          self.notifies :run, "bash[horizon-database-sync]", :immediately
          self.resolve_notification_references
      end
      not_if { system "MYSQL_PWD=#{get_config('mysql-root-password')} mysql -uroot -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['dbname']['horizon']}\"'|grep \"#{node['bcpc']['dbname']['horizon']}\" >/dev/null" }
  end

  bash "horizon-database-sync" do
      action :nothing
      user "root"
      code "/usr/share/openstack-dashboard/manage.py syncdb --noinput"
      notifies :restart, "service[apache2]", :immediately
  end
end

# needed to regenerate the static assets for the dashboard
bash "dpkg-reconfigure-openstack-dashboard" do
    action :nothing
    user "root"
    code "dpkg-reconfigure openstack-dashboard"
    notifies :restart, "service[apache2]", :immediately
end

# troveclient gets installed by something and can blow up Horizon startup
# if not upgraded when moving from Kilo to Liberty
package 'python-troveclient' do
  action :upgrade
  notifies :restart, "service[apache2]", :immediately
end
