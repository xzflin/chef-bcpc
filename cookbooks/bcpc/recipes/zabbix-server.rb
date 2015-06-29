#
# Cookbook Name:: bcpc
# Recipe:: zabbix-server
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

if node['bcpc']['enabled']['monitoring'] then
    include_recipe "bcpc::mysql-monitoring"
    include_recipe "bcpc::apache2"
    include_recipe "bcpc::packages-zabbix"

    ruby_block "initialize-zabbix-config" do
        block do
            make_config('mysql-zabbix-user', "zabbix")
            make_config('mysql-zabbix-password', secure_password)
            make_config('zabbix-admin-user', "admin")
            make_config('zabbix-admin-password', secure_password)
            make_config('zabbix-guest-user', "guest")
            make_config('zabbix-guest-password', secure_password)
        end
    end
    
    # this script removes the old manually compiled Zabbix server installation
    # (being a bit lazy and assuming the presence of the old server binary signals everything
    # is still there)
    bash "clean-up-old-zabbix-server" do
        code <<-EOH
          service zabbix-server stop
          rm -f /usr/local/etc/server.conf
          rm -f /usr/local/sbin/zabbix_server
          rm -f /usr/local/share/man/man8/zabbix_server.8
          rm -rf /usr/local/share/zabbix
          rm -rf /usr/local/etc/zabbix_server.conf.d
          rm -f /tmp/zabbix-server.tar.gz
          rm -f /etc/init/zabbix-server.conf
        EOH
        only_if 'test -f /usr/local/sbin/zabbix_server'
    end

    user node['bcpc']['zabbix']['user'] do
        shell "/bin/false"
        home "/var/log"
        gid node['bcpc']['zabbix']['group']
        system true
    end

    %w{zabbix-server-mysql zabbix-frontend-php}.each do |zabbix_package|
      package zabbix_package do
        action :upgrade
        # no-install-recommends used here because zabbix-server-mysql wants to remove
        # Percona packages in favor of non-clustered Oracle MySQL otherwise
        options "--no-install-recommends"
      end
    end
    
    # move the package's sysvinit startup script to another name
    bash 'move-zabbix-server-mysql-startup-script' do
      code <<-EOH
        mv /etc/init.d/zabbix-server /etc/init.d/zabbix-server-sysvinit
      EOH
      not_if 'test -f /etc/init.d/zabbix-server-sysvinit'
    end

    directory "/var/log/zabbix" do
        user node['bcpc']['zabbix']['user']
        group node['bcpc']['zabbix']['group']
        mode 00755
    end

    template "/etc/zabbix/zabbix_server.conf" do
        source "zabbix_server.conf.erb"
        owner node['bcpc']['zabbix']['user']
        group "root"
        mode 00600
        notifies :restart, "service[zabbix-server]", :delayed
    end

    ruby_block "zabbix-database-creation" do
        block do
            if not system "mysql -uroot -p#{get_config('mysql-monitoring-root-password')} -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['dbname']['zabbix']}\"'|grep \"#{node['bcpc']['dbname']['zabbix']}\"" then
                %x[ mysql -uroot -p#{get_config('mysql-monitoring-root-password')} -e "CREATE DATABASE #{node['bcpc']['dbname']['zabbix']} CHARACTER SET UTF8;"
                    mysql -uroot -p#{get_config('mysql-monitoring-root-password')} -e "GRANT ALL ON #{node['bcpc']['dbname']['zabbix']}.* TO '#{get_config('mysql-zabbix-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-zabbix-password')}';"
                    mysql -uroot -p#{get_config('mysql-monitoring-root-password')} -e "GRANT ALL ON #{node['bcpc']['dbname']['zabbix']}.* TO '#{get_config('mysql-zabbix-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-zabbix-password')}';"
                    mysql -uroot -p#{get_config('mysql-monitoring-root-password')} -e "FLUSH PRIVILEGES;"
                    mysql -uroot -p#{get_config('mysql-monitoring-root-password')} #{node['bcpc']['dbname']['zabbix']} < /usr/share/zabbix-server-mysql/schema.sql
                    mysql -uroot -p#{get_config('mysql-monitoring-root-password')} #{node['bcpc']['dbname']['zabbix']} < /usr/share/zabbix-server-mysql/images.sql
                    mysql -uroot -p#{get_config('mysql-monitoring-root-password')} #{node['bcpc']['dbname']['zabbix']} < /usr/share/zabbix-server-mysql/data.sql
                    HASH=`echo -n "#{get_config('zabbix-admin-password')}" | md5sum | awk '{print $1}'`
                    mysql -uroot -p#{get_config('mysql-monitoring-root-password')} #{node['bcpc']['dbname']['zabbix']} -e "UPDATE users SET passwd=\\"$HASH\\" WHERE alias=\\"#{get_config('zabbix-admin-user')}\\";"
                    HASH=`echo -n "#{get_config('zabbix-guest-password')}" | md5sum | awk '{print $1}'`
                    mysql -uroot -p#{get_config('mysql-monitoring-root-password')} #{node['bcpc']['dbname']['zabbix']} -e "UPDATE users SET passwd=\\"$HASH\\" WHERE alias=\\"#{get_config('zabbix-guest-user')}\\";"
                ]
            end
        end
    end
    
    # Upstart job is maintained under a name different from the SysV init script 
    # so that it continues to interact nicely with keepalived
    template '/etc/init/zabbix-server.conf' do
      source   'upstart-zabbix-server.conf.erb'
      owner    'root'
      group    'root'
      notifies :restart, 'service[zabbix-server]', :delayed
    end

    # disable the sysvinit version from automatic startup
    service 'zabbix-server-sysvinit' do
      action [:disable, :stop]
    end

    # do automatic service startup via the Upstart wrapper
    service 'zabbix-server' do
        action          [:enable, :start]
        start_command   'service zabbix-server start'
        restart_command 'service zabbix-server restart'
    end

    %w{traceroute php5-mysql php5-gd python-requests}.each do |pkg|
        package pkg do
            action :upgrade
        end
    end

    file "/etc/php5/apache2/conf.d/zabbix.ini" do
        user "root"
        group "root"
        mode 00644
        content <<-EOH
            post_max_size = 16M
            max_execution_time = 300
            max_input_time = 300
            date.timezone = America/New_York
        EOH
        notifies :restart, "service[apache2]", :delayed
    end

    template "/etc/zabbix/web/zabbix.conf.php" do
        source "zabbix.conf.php.erb"
        user node['bcpc']['zabbix']['user']
        group "www-data"
        mode 00640
        notifies :restart, "service[apache2]", :delayed
    end

    template "/etc/apache2/sites-available/zabbix-web.conf" do
        source "apache-zabbix-web.conf.erb"
        owner "root"
        group "root"
        mode 00644
        notifies :restart, "service[apache2]", :delayed
    end

    bash "apache-enable-zabbix-web" do
        user "root"
        code <<-EOH
             a2ensite zabbix-web
        EOH
        not_if "test -r /etc/apache2/sites-enabled/zabbix-web"
        notifies :restart, "service[apache2]", :immediate
    end

    directory "/usr/local/lib/python2.7/dist-packages/pyzabbix" do
        owner "root"
        mode 00775
    end

    cookbook_file "/usr/local/lib/python2.7/dist-packages/pyzabbix/__init__.py" do
        source "pyzabbix.py"
        owner "root"
        mode 00755
    end

    cookbook_file "/tmp/zabbix_linux_active_template.xml" do
        source "zabbix_linux_active_template.xml"
        owner "root"
        mode 00644
    end

    cookbook_file "/tmp/zabbix_bcpc_templates.xml" do
        source "zabbix_bcpc_templates.xml"
        owner "root"
        mode 00644
    end

    cookbook_file "/usr/local/bin/zabbix_config" do
        source "zabbix_config"
        owner "root"
        mode 00755
    end

    ruby_block "configure_zabbix_templates" do
        block do
            # Ensures no proxy is ever used locally
            %x[export no_proxy="#{node['bcpc']['management']['monitoring']['vip']}";
               zabbix_config https://#{node['bcpc']['management']['monitoring']['vip']}/zabbix #{get_config('zabbix-admin-user')} #{get_config('zabbix-admin-password')}
            ]
        end
    end

    template "/usr/share/zabbix/zabbix-api-auto-discovery" do
        source "zabbix_api_auto_discovery.erb"
        owner "root"
        group "root"
        mode 00750
    end

    ruby_block "zabbix-api-auto-discovery-register" do
        block do
            # Ensures no proxy is ever used locally
            %x[export no_proxy="#{node['bcpc']['management']['monitoring']['vip']}";
               /usr/share/zabbix/zabbix-api-auto-discovery
            ]
        end
    end
    
    # terminate the Zabbix server if this server doesn't hold the monitoring VIP
    # (this is a safeguard to get out of a potential weird state immediately after
    # migrating from compiled Zabbix to packaged Zabbix)
    bash "stop-zabbix-server-if-not-monitoring-vip" do
      code <<-EOH
        if ! service zabbix-server status | grep -q stop/waiting; then 
          if_not_monitoring_vip service zabbix-server stop
        fi
      EOH
    end
end
