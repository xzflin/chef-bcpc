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

# are we performing an upgrade from Kilo to Liberty?
kilo_to_liberty_upgrade_check = Mixlib::ShellOut.new("dpkg --compare-versions $(dpkg -s python-nova | egrep '^Version:' | awk '{ print $NF }') lt 2:12.0.0")
kilo_to_liberty_upgrade_check.run_command
if !kilo_to_liberty_upgrade_check.error? && node['bcpc']['openstack_release'] == 'liberty'
  file '/usr/local/etc/kilo_to_liberty_upgrade'
end

# python-nova will be used as the canary package to determine whether at least
# 2015.1.2 is being installed
ruby_block 'evaluate-version-eligibility' do
  block do
    minimum_nova_version = Mixlib::ShellOut.new("dpkg --compare-versions $(apt-cache show --no-all-versions python-nova | egrep '^Version:' | awk '{ print $NF }') ge 1:2015.1.2")
    cmd_result = minimum_nova_version.run_command
    fail('You must install OpenStack Kilo 2015.1.2 or better. Earlier versions are not supported.') if cmd_result.error?
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

%w{control_openstack hup_openstack logwatch}.each do |script|
    template "/usr/local/bin/#{script}" do
        source "#{script}.erb"
        mode 0755
        owner "root"
        group "root"
        variables(:servers => get_head_nodes)
    end
end
