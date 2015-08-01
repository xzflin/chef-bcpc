include_recipe "bcpc::ceph-work"

%w{ssd hdd}.each do |type|
    node['bcpc']['ceph']["#{type}_disks"].each do |disk|
        execute "ceph-disk-prepare-#{type}-#{disk}" do
            command <<-EOH
                ceph-disk-prepare /dev/#{disk}
                ceph-disk-activate /dev/#{disk}
                sleep 2
                INFO=`df -k | grep /dev/#{disk} | awk '{print $2,$6}' | sed -e 's/\\/var\\/lib\\/ceph\\/osd\\/ceph-//'`
                OSD=${INFO#* }
                WEIGHT=`echo "scale=4; ${INFO% *}/1000000000.0" | bc -q`
                ceph osd crush create-or-move $OSD $WEIGHT root=#{type} rack=#{node['bcpc']['rack_name']}-#{type} host=#{node['hostname']}-#{type}
            EOH
            not_if "sgdisk -i1 /dev/#{disk} | grep -i 4fbd7e29-9d25-41b8-afd0-062c0ceff05d"
        end
    end
end

execute "trigger-osd-startup" do
    command "udevadm trigger --subsystem-match=block --action=add"
end

ruby_block "reap-ceph-disks-from-dead-servers" do
    block do
        storage_ips = search_nodes("recipe", "ceph-osd").collect { |x| x['bcpc']['storage']['ip'] }
        status = JSON.parse(%x[ceph osd dump --format=json])
        status['osds'].select { |x| x['up']==0 && x['in']==0 }.each do |osd|
            osd_ip = osd['public_addr'][/[^:]*/]
            if osd_ip != "" and not storage_ips.include?(osd_ip)
                %x[
                    ceph osd crush remove osd.#{osd['osd']}
                    ceph osd rm osd.#{osd['osd']}
                    ceph auth del osd.#{osd['osd']}
                ]
            end
        end
    end
end

template '/etc/init/ceph-osd-renice.conf' do
  source 'ceph-upstart.ceph-osd-renice.conf.erb'
  mode 00644
  notifies :restart, "service[ceph-osd-renice]", :immediately
end

service 'ceph-osd-renice' do
  provider Chef::Provider::Service::Upstart
  action [:enable, :start]
  restart_command 'service ceph-osd-renice restart'
end

# this resource is to clean up leftovers from the CephFS resources that used to be here
bash "clean-up-cephfs-mountpoint" do
  code "sed -i 's/^-- \\/mnt fuse\\.ceph-fuse rw,nosuid,nodev,noexec,noatime,noauto 0 2$//g' /etc/fstab"
  only_if { system "grep -q -e '^-- \\/mnt fuse\\.ceph-fuse rw,nosuid,nodev,noexec,noatime,noauto 0 2$' /etc/fstab" }
end
