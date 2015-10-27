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
end

template "/var/lib/cobbler/kickstarts/bcpc_ubuntu_host.preseed" do
    source "cobbler.bcpc_ubuntu_host.preseed.erb"
    mode 00644
    variables(:bootstrap_node => get_bootstrap_node)
end

cookbook_file "#{Chef::Config[:file_cache_path]}/ubuntu-14.04-mini.iso" do
    source "bins/ubuntu-14.04-mini.iso"
    owner "root"
    mode 00444
end

# Get syslinux supporting files
cookbook_file "#{Chef::Config[:file_cache_path]}/syslinux-6.03.tar.gz" do
    source "bins/syslinux-6.03.tar.gz"
    owner "root"
    mode 00444
end

bash "unpack-syslinux-files" do
    user "root"
    code <<-EOH
        cd #{Chef::Config[:file_cache_path]}
        tar xzf syslinux-6.03.tar.gz
    EOH
end

# Add post-sync trigger
cookbook_file "/usr/lib/python2.7/dist-packages/cobbler/modules/sync_post_copy_pxe_configs.py" do
    source "sync_post_copy_pxe_configs.py"
    owner "root"
    mode "0644"
    notifies :reload, "service[cobbler]", :delayed
end

# Create and populate boot-mode specific state dir structure
directory "/var/lib/tftpboot" do
    owner "root"
    group "root"
    mode "0755"
    action "create"
end

%w{ bios efi64 }.each do |bootmode|
    directory "/var/lib/tftpboot/#{bootmode}" do
        owner "root"
        group "root"
        mode "0755"
        action "create"
    end
end


bash "install-syslinux-bios-files" do
    code <<-EOH
        cd #{Chef::Config[:file_cache_path]}
        cp syslinux-6.03/bios/core/pxelinux.0 /var/lib/tftpboot/bios/
        cp syslinux-6.03/bios/com32/elflink/ldlinux/ldlinux.c32 /var/lib/tftpboot/bios/
        cp syslinux-6.03/bios/com32/lib/libcom32.c32 /var/lib/tftpboot/bios/
        cp syslinux-6.03/bios/com32/libutil/libutil.c32 /var/lib/tftpboot/bios/
        cp syslinux-6.03/bios/com32/menu/vesamenu.c32 /var/lib/tftpboot/bios/
        cp syslinux-6.03/bios/com32/modules/pxechn.c32 /var/lib/tftpboot/bios/
    EOH
end

bash "install-syslinux-efi64-files" do
    code <<-EOH
        cd #{Chef::Config[:file_cache_path]}
        cp syslinux-6.03/efi64/efi/syslinux.efi /var/lib/tftpboot/efi64/
        cp syslinux-6.03/efi64/com32/elflink/ldlinux/ldlinux.e64 /var/lib/tftpboot/efi64/
        cp syslinux-6.03/efi64/com32/lib/libcom32.c32 /var/lib/tftpboot/efi64/
        cp syslinux-6.03/efi64/com32/libutil/libutil.c32 /var/lib/tftpboot/efi64/
        cp syslinux-6.03/efi64/com32/menu/vesamenu.c32 /var/lib/tftpboot/efi64/
        cp syslinux-6.03/efi64/com32/modules/pxechn.c32 /var/lib/tftpboot/efi64/
    EOH
end

bash "import-ubuntu-distribution-cobbler" do
    user "root"
    code <<-EOH
        mkdir -p /mnt/iso
        mount -o loop -o ro /tmp/ubuntu-14.04-mini.iso /mnt/iso
        cobbler import --name=ubuntu-14.04-mini --path=/mnt/iso --breed=ubuntu --os-version=trusty --arch=x86_64
        umount /mnt/iso
        rmdir /mnt/iso
        cobbler sync
    EOH
    not_if "cobbler distro list | grep ubuntu-14.04-mini"
end

bash "import-bcpc-profile-cobbler" do
    user "root"
    code <<-EOH
        cobbler profile add --name=bcpc_host --distro=ubuntu-14.04-mini-x86_64 --kickstart=/var/lib/cobbler/kickstarts/bcpc_ubuntu_host.preseed --kopts="interface=auto"
        cobbler sync
    EOH
    not_if "cobbler profile list | grep -w bcpc_host"
end

service "isc-dhcp-server" do
    action [:enable, :start]
end

service "cobbler" do
    provider Chef::Provider::Service::Upstart
    action [:enable, :start]
end
