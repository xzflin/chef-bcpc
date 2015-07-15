include_recipe "bcpc::checks-common"

%w{ rgw mysql }.each do |cc|
    template  "/usr/local/etc/checks/#{cc}.yml" do
        source "checks/#{cc}.yml.erb"
        owner "root"
        group "zabbix"
        mode 00640
    end

    cookbook_file "/usr/local/bin/checks/#{cc}" do
        source "checks/#{cc}"
        owner "root"
        mode "00755"
    end
end

if node['bcpc']['enabled']['monitoring'] then
    %w{ nova rgw }.each do |cc|
        cron "check-#{cc}" do
            home "/var/lib/zabbix"
            user "zabbix"
            minute "*/10"
            path "/usr/local/bin:/usr/bin:/bin"
            command "zabbix_sender -c /etc/zabbix/zabbix_agentd.conf --key 'check.#{cc}' --value `check -f timeonly #{cc}` 2>&1 | /usr/bin/logger -p local0.notice"
        end
    end
end
