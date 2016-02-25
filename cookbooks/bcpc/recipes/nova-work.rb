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
include_recipe "bcpc::ceph-work"
include_recipe "bcpc::nova-common"

package "nova-compute-#{node['bcpc']['virt_type']}" do
    action :upgrade
end

%w{nova-api nova-network nova-compute nova-novncproxy}.each do |pkg|
    package pkg do
        action :upgrade
    end
    service pkg do
        action [:enable, :start]
        subscribes :restart, "template[/etc/nova/nova.conf]", :delayed
        subscribes :restart, "template[/etc/nova/api-paste.ini]", :delayed
        subscribes :restart, "template[/etc/nova/policy.json]", :delayed
    end
end

service "nova-api" do
    restart_command "service nova-api restart; sleep 5"
end

%w{novnc pm-utils memcached sysfsutils}.each do |pkg|
    package pkg do
        action :upgrade
    end
end

template "/etc/nova/ssl-bcpc.pem" do
    source "ssl-bcpc.pem.erb"
    owner "nova"
    group "nova"
    mode 00644
end

template "/etc/nova/ssl-bcpc.key" do
    source "ssl-bcpc.key.erb"
    owner "nova"
    group "nova"
    mode 00600
end

directory "/var/lib/nova/.ssh" do
    owner "nova"
    group "nova"
    mode 00700
end

template "/var/lib/nova/.ssh/authorized_keys" do
    source "nova-authorized_keys.erb"
    owner "nova"
    group "nova"
    mode 00644
end

template "/var/lib/nova/.ssh/known_hosts" do
    source "known_hosts.erb"
    owner "nova"
    group "nova"
    mode 00644
    variables(:servers => search_nodes("recipe", "nova-work"))
end

template "/var/lib/nova/.ssh/id_rsa" do
    source "nova-id_rsa.erb"
    owner "nova"
    group "nova"
    mode 00600
end

template "/var/lib/nova/.ssh/config" do
    source "nova-ssh_config.erb"
    owner "nova"
    group "nova"
    mode 00600
end

template "/etc/default/libvirt-bin" do
  source "libvirt-bin-default.erb"
  owner "root"
  group "root"
  mode 00644
  notifies :restart, "service[libvirt-bin]", :delayed
end

template "/etc/libvirt/libvirtd.conf" do
    source "libvirtd.conf.erb"
    owner "root"
    group "root"
    mode 00644
    notifies :restart, "service[libvirt-bin]", :delayed
end

service "libvirt-bin" do
    action [:enable, :start]
    restart_command "/etc/init.d/libvirt-bin restart"
end

template "/etc/nova/virsh-secret.xml" do
    source "virsh-secret.xml.erb"
    owner "nova"
    group "nova"
    mode 00600
end

bash "set-nova-user-shell" do
    user "root"
    code <<-EOH
        chsh -s /bin/bash nova
    EOH
    not_if "grep nova /etc/passwd | grep /bin/bash"
end

template "/etc/ceph/ceph.client.cinder.keyring" do
  source "ceph-client-cinder-keyring.erb"
  mode "00644"
end

ruby_block 'load-virsh-keys' do
    block do
        %x[ CINDER_KEY=`ceph --name mon. --keyring /etc/ceph/ceph.mon.keyring auth get-or-create-key client.cinder`
            virsh secret-define --file /etc/nova/virsh-secret.xml
            virsh secret-set-value --secret #{get_config('libvirt-secret-uuid')} --base64 "$CINDER_KEY"
        ]
    end
    not_if { system "virsh secret-list | grep -i #{get_config('libvirt-secret-uuid')} >/dev/null" }
end

bash "remove-default-virsh-net" do
    user "root"
    code <<-EOH
        virsh net-destroy default
        virsh net-undefine default
    EOH
    only_if "virsh net-list | grep -i default"
end

bash "libvirt-device-acls" do
    user "root"
    code <<-EOH
        echo "cgroup_device_acl = [" >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/null\\\", \\\"/dev/full\\\", \\\"/dev/zero\\\"," >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/random\\\", \\\"/dev/urandom\\\"," >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/ptmx\\\", \\\"/dev/kvm\\\", \\\"/dev/kqemu\\\"," >> /etc/libvirt/qemu.conf
        echo "   \\\"/dev/rtc\\\", \\\"/dev/hpet\\\", \\\"/dev/net/tun\\\"" >> /etc/libvirt/qemu.conf
        echo "]" >> /etc/libvirt/qemu.conf
    EOH
    not_if "grep -e '^cgroup_device_acl' /etc/libvirt/qemu.conf"
    notifies :restart, "service[libvirt-bin]", :delayed
end

# we have to adjust apparmor to allow qemu to write rbd logs/sockets
service "apparmor" do
  action :nothing
end

template "/etc/apparmor.d/abstractions/libvirt-qemu" do
  source "apparmor-libvirt-qemu.#{node['bcpc']['openstack_release']}.erb"
  notifies :restart, "service[libvirt-bin]", :delayed
  notifies :restart, "service[apparmor]", :delayed
end

if node['bcpc']['virt_type'] == "kvm" then
    %w{amd intel}.each do |arch|
        bash "enable-kvm-#{arch}" do
            user "root"
            code <<-EOH
                modprobe kvm_#{arch}
                echo 'kvm_#{arch}' >> /etc/modules
            EOH
            not_if "grep -e '^kvm_#{arch}' /etc/modules"
        end
    end
end

cron "restart-nova-kludge" do
  action :delete
end

file "/usr/local/bin/nova-service-restart" do
  action :delete
end

file "/usr/local/bin/nova-service-restart-wrapper" do
  action :delete
end

# patch Nova metadata for our hostname format (ip-x-x-x-x and public-x-x-x-x)
bcpc_patch 'nova-api-metadata-base-kilo' do
  patch_file           'nova-api-metadata-base.patch'
  patch_root_dir       '/usr/lib/python2.7/dist-packages'
  shasums_before_apply 'nova-api-metadata-base-kilo-BEFORE.SHASUMS'
  shasums_after_apply  'nova-api-metadata-base-kilo-AFTER.SHASUMS'
  notifies :restart, 'service[nova-api]', :immediately
  only_if "dpkg --compare-versions $(dpkg -s python-nova | egrep '^Version:' | awk '{ print $NF }') lt 2:0"
end

# two different sets of checksums for Liberty (12.0.0 has one, 12.0.1+ another)
# NOTE: SHASUM for base.py in Git is _different_ from package (somebody moved a line
# in the packaged version)
bcpc_patch 'nova-api-metadata-base-liberty-12.0.0' do
  patch_file           'nova-api-metadata-base.patch'
  patch_root_dir       '/usr/lib/python2.7/dist-packages'
  shasums_before_apply 'nova-api-metadata-base-liberty-12.0.0-BEFORE.SHASUMS'
  shasums_after_apply  'nova-api-metadata-base-liberty-12.0.0-AFTER.SHASUMS'
  notifies :restart, 'service[nova-api]', :immediately
  only_if "dpkg --compare-versions $(dpkg -s python-nova | egrep '^Version:' | awk '{ print $NF }') eq 2:12.0.0-0ubuntu1~cloud0"
end

bcpc_patch 'nova-api-metadata-base-liberty-12.0.1-plus' do
  patch_file           'nova-api-metadata-base.patch'
  patch_root_dir       '/usr/lib/python2.7/dist-packages'
  shasums_before_apply 'nova-api-metadata-base-liberty-12.0.1-plus-BEFORE.SHASUMS'
  shasums_after_apply  'nova-api-metadata-base-liberty-12.0.1-plus-AFTER.SHASUMS'
  notifies :restart, 'service[nova-api]', :immediately
  only_if "dpkg --compare-versions $(dpkg -s python-nova | egrep '^Version:' | awk '{ print $NF }') ge 2:12.0.1-0ubuntu1~cloud0"
end

# Remove patch files used by older patching resource
file "/usr/lib/python2.7/dist-packages/nova/network/linux_net.py.prepatch" do
  action :delete
end

file "/usr/lib/python2.7/dist-packages/nova_network_linux_net.patch" do
  action :delete
end

# This patches nova-network to have dnsmasq bind to the tenant's bridged
# interface, so unicast DHCP replies are correctly responded to.
# This presumes linux_net.py has the BCPC hostnames patch applied by an
# earlier version of this recipe (Kilo only).
bcpc_patch "nova-network-linux_net-dnsmasq" do
  patch_file           'nova-network-linux_net-dnsmasq.patch'
  patch_root_dir       '/usr/lib/python2.7/dist-packages'
  shasums_before_apply 'nova-network-linux_net-dnsmasq-BEFORE.SHASUMS'
  shasums_after_apply  'nova-network-linux_net-dnsmasq-AFTER.SHASUMS'
  notifies :restart, 'service[nova-network]', :immediately
  only_if "shasum /usr/lib/python2.7/dist-packages/nova/network/linux_net.py | grep -q '^78337cd95c476de57b9eede2350a67dd780fb239'"
end

# This patches the stock nova-network linux_net.py with BCPC hostname
# change and the above dnsmasq fix
# This is duplicated for 2015.1.3, 2015.1.4 for expediency
bcpc_patch "nova-network-linux_net-2015.1.[2-3]" do
  patch_file           'nova-network-linux_net-2015.1.3.patch'
  patch_root_dir       '/usr/lib/python2.7/dist-packages'
  shasums_before_apply 'nova-network-linux_net-2015.1.3-BEFORE.SHASUMS'
  shasums_after_apply  'nova-network-linux_net-2015.1.3-AFTER.SHASUMS'
  notifies :restart, 'service[nova-network]', :immediately
  only_if { %w(1:2015.1.2-0ubuntu2~cloud0 1:2015.1.3-0ubuntu1).include? %x[dpkg-query -W -f '${Version}' python-nova] }
end

bcpc_patch "nova-network-linux_net-2015.1.4" do
  patch_file           'nova-network-linux_net-2015.1.4.patch'
  patch_root_dir       '/usr/lib/python2.7/dist-packages'
  shasums_before_apply 'nova-network-linux_net-2015.1.4-BEFORE.SHASUMS'
  shasums_after_apply  'nova-network-linux_net-2015.1.4-AFTER.SHASUMS'
  notifies :restart, 'service[nova-network]', :immediately
  only_if { %x[dpkg-query -W -f '${Version}' python-nova] == "1:2015.1.4-0ubuntu1"}
end

bcpc_patch "nova-network-liberty-linux_net" do
  patch_file           'nova-network-liberty-linux_net.patch'
  patch_root_dir       '/usr/lib/python2.7/dist-packages'
  shasums_before_apply 'nova-network-liberty-linux_net-BEFORE.SHASUMS'
  shasums_after_apply  'nova-network-liberty-linux_net-AFTER.SHASUMS'
  notifies :restart, 'service[nova-network]', :immediately
  only_if "dpkg --compare-versions $(dpkg -s python-nova | egrep '^Version:' | awk '{ print $NF }') ge 2:0"
end
