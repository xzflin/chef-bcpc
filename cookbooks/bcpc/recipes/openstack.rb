#
# Cookbook Name:: bcpc
# Recipe:: openstack
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

include_recipe "bcpc::default"
include_recipe "bcpc::packages-openstack"

# are we performing an upgrade to Liberty/Mitaka?
upgrade_check_version = \
  if is_mitaka?
    '2:13.0.0'
  else
    '2:12.0.0'
  end

upgrade_check = Mixlib::ShellOut.new("dpkg --compare-versions $(dpkg -s python-nova | egrep '^Version:' | awk '{ print $NF }') lt #{upgrade_check_version}")
upgrade_check.run_command
if !upgrade_check.error?
  file '/usr/local/etc/openstack_upgrade' do
    notifies :run, 'bash[clean-old-pyc-files]', :immediately
  end
end

bash 'clean-old-pyc-files' do
  code 'find /usr/lib/python2.7/dist-packages -name \*.pyc -delete'
  action :nothing
end

# python-nova is used as the canary package
min_version = \
  if is_kilo?
    '1:2015.1.2'
  elsif is_liberty?
    '2:12.0.0'
  elsif is_mitaka?
    '2:13.1.1'
  else
    raise "You are attempting to install an unsupported OpenStack version."
  end

ruby_block 'evaluate-version-eligibility' do
  block do
    minimum_nova_version = Mixlib::ShellOut.new("dpkg --compare-versions $(apt-cache show --no-all-versions python-nova | egrep '^Version:' | awk '{ print $NF }') ge #{min_version}")
    cmd_result = minimum_nova_version.run_command
    fail("You must install OpenStack #{node['bcpc']['openstack_release']} #{min_version} or better. Earlier versions are not supported.") if cmd_result.error?
  end
end

%w{ python-novaclient
    python-cinderclient
    python-glanceclient
    python-memcache
    python-keystoneclient
    python-nova-adminclient
    python-heatclient
    python-ceilometerclient
    python-mysqldb
    python-six
    python-ldap
    python-openstackclient
}.each do |pkg|
    package pkg do
        action :upgrade
    end
end

# remove cliff-tablib from Mitaka and beyond because it collides with built-in formatters
package 'cliff-tablib' do
  action :remove
  not_if { is_kilo? || is_liberty? }
end

%w{control_openstack hup_openstack logwatch}.each do |script|
    template "/usr/local/bin/#{script}" do
        source "#{script}.erb"
        mode 0755
        owner "root"
        group "root"
        variables(:servers => get_head_nodes)
    end
end
