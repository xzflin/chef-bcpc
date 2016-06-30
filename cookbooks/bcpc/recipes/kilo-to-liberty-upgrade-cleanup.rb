#
# Cookbook Name:: bcpc
# Recipe:: kilo-to-liberty-upgrade-cleanup
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

bash 'clean-out-pyc-files-after-upgrade' do
  code 'find /usr/lib/python2.7/dist-packages -name \*.pyc -delete'
  only_if { ::File.exist?('/usr/local/etc/kilo_to_liberty_upgrade') }
end

bash 'hup-openstack-after-upgrade' do
  code '/usr/local/bin/hup_openstack'
  only_if { ::File.exist?('/usr/local/etc/kilo_to_liberty_upgrade') }
end

file 'cleanup-kilo_to_liberty_upgrade-lockfile' do
  path '/usr/local/etc/kilo_to_liberty_upgrade'
  action :delete
end
