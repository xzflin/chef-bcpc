#
# Cookbook Name:: bcpc
# Recipe:: cobbler
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

# for mkpasswd
package "whois"

ruby_block "initialize-cobbler-config" do
    block do
        make_config('cobbler-web-user', "cobbler")
        make_config('cobbler-web-password', secure_password)
        make_config('cobbler-web-password-digest', %x[ printf "#{get_config('cobbler-web-user')}:Cobbler:#{get_config('cobbler-web-password')}" | md5sum | awk '{print $1}' ])
        make_config('cobbler-root-password', secure_password)
        make_config('cobbler-root-password-salted', %x[ printf "#{get_config('cobbler-root-password')}" | mkpasswd -s -m sha-512 ])
    end
end

package "isc-dhcp-server"
package "cobbler"
package "cobbler-web"

template "/etc/cobbler/settings" do
    source "cobbler.settings.erb"
    mode 00644
    notifies :restart, "service[cobbler]", :delayed
end

template "/etc/cobbler/users.digest" do
    source "cobbler.users.digest.erb"
    mode 00600
end

template "/etc/cobbler/dhcp.template" do
    source "cobbler.dhcp.template.erb"
    mode 00644
    variables(
        :range => node['bcpc']['bootstrap']['dhcp_range'],
        :subnet => node['bcpc']['bootstrap']['dhcp_subnet']
    )
    notifies :restart, "service[cobbler]", :delayed
    notifies :run, "bash[run-cobbler-sync]", :immediately
end

node['bcpc']['cobbler']['kickstarts'].each do |kickstart|
  template "/var/lib/cobbler/kickstarts/#{kickstart}" do
    source "cobbler.#{kickstart}.erb"
    mode 00644
    variables(:bootstrap_node => get_bootstrap_node)
  end
end

node['bcpc']['cobbler']['distributions'].each do |distro, distro_attrs|
  iso_path = ::File.join(
    Chef::Config['file_cache_path'], "#{distro}.iso")

  # add thing here to figure out whether to source from cookbook or web URI
  if distro_attrs['iso_source'] == 'bcpc-binary-files'
    cookbook_file iso_path do
      source   distro_attrs['source']
      cookbook 'bcpc-binary-files'
      owner    'root'
      group    'root'
      mode     00444
    end
  elsif distro_attrs['iso_source'] == 'uri'
    remote_file iso_path do
      source   distro_attrs['source']
      checksum distro_attrs['shasum']
      owner    'root'
      group    'root'
      mode     00444
    end
  else
    raise "#{distro_attrs['iso_source']} is not an acceptable ISO source, "
          "must be either 'bcpc-binary-files' or 'uri'"
  end

  bash "import-cobbler-distribution-#{distro}" do
    user "root"
    code <<-EOH
      mount -o loop -o ro #{iso_path} /mnt
      cobbler import --name=#{distro} --path=/mnt \
        --breed=#{distro_attrs['breed']} \
        --os-version=#{distro_attrs['os_version']} \
        --arch=#{distro_attrs['arch']}
      umount /mnt
    EOH
    not_if "cobbler distro list | awk '{ print $1 }' | grep '^#{distro}-#{distro_attrs['arch']}$'"
    notifies :run, "bash[run-cobbler-sync]", :immediately
  end
end

node['bcpc']['cobbler']['profiles'].each do |profile, profile_attrs|
  bash "import-bcpc-cobbler-profile-#{profile}" do
    user "root"
    code <<-EOH
      cobbler profile add --name=#{profile} \
      --distro=#{profile_attrs['distro']} \
      --kickstart=/var/lib/cobbler/kickstarts/#{profile_attrs['kickstart']} \
      --kopts="interface=auto"
    EOH
    not_if "cobbler profile list | awk '{ print $1 }' | grep '^#{profile}$'"
    notifies :run, "bash[run-cobbler-sync]", :immediately
  end
end

service "isc-dhcp-server" do
    action [:enable, :start]
end

service "cobbler" do
    action [:enable, :start]
end

bash "run-cobbler-sync" do
  code "cobbler sync"
  action :nothing
end
