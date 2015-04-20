#
# Cookbook Name:: bcpc
# Recipe:: powerdns
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

if node['bcpc']['enabled']['dns'] then

    ruby_block "initialize-powerdns-config" do
        block do
            make_config('mysql-pdns-user', "pdns")
            make_config('mysql-pdns-password', secure_password)
        end
    end

    %w{pdns-server pdns-backend-mysql}.each do |pkg|
        package pkg do
            action :upgrade
        end
    end

    # needed for populate_dns.py
    package "python-mysqldb" do
        action :upgrade
    end

    template "/etc/powerdns/pdns.conf" do
        source "pdns.conf.erb"
        owner "root"
        group "root"
        mode 00600
        notifies :restart, "service[pdns]", :delayed
    end

    # the presence of this file can interfere with the other configurations, so explicitly remove it
    file "/etc/powerdns/pdns.d/pdns.local.gmysql.conf" do
      action :delete
      notifies :restart, "service[pdns]", :delayed
    end

    ruby_block "powerdns-database-creation" do
        block do
            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT SCHEMA_NAME FROM INFORMATION_SCHEMA.SCHEMATA WHERE SCHEMA_NAME = \"#{node['bcpc']['dbname']['pdns']}\"' | grep -q \"#{node['bcpc']['dbname']['pdns']}\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} -e "CREATE DATABASE #{node['bcpc']['dbname']['pdns']} CHARACTER SET utf8 COLLATE utf8_general_ci;"
                    mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['dbname']['pdns']}.* TO '#{get_config('mysql-pdns-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-pdns-password')}';"
                    mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['dbname']['pdns']}.* TO '#{get_config('mysql-pdns-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-pdns-password')}';"
                    mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['dbname']['nova']}.* TO '#{get_config('mysql-pdns-user')}'@'%' IDENTIFIED BY '#{get_config('mysql-pdns-password')}';"
                    mysql -uroot -p#{get_config('mysql-root-password')} -e "GRANT ALL ON #{node['bcpc']['dbname']['nova']}.* TO '#{get_config('mysql-pdns-user')}'@'localhost' IDENTIFIED BY '#{get_config('mysql-pdns-password')}';"
                    mysql -uroot -p#{get_config('mysql-root-password')} -e "FLUSH PRIVILEGES;"
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end

    ruby_block "powerdns-table-keystone_project" do
        block do

            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = \"#{node['bcpc']['dbname']['pdns']}\" AND TABLE_NAME=\"keystone_project\"' | grep -q \"keystone_project\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                    CREATE TABLE IF NOT EXISTS keystone_project (
                        id VARCHAR(255) NOT NULL,
                        name VARCHAR(255) NOT NULL
                    );
                    CREATE UNIQUE INDEX keystone_project_name ON keystone_project(name);
                    CREATE UNIQUE INDEX keystone_project_id on keystone_project(id);
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end

    ruby_block "powerdns-table-domains" do
        block do

            reverse_dns_zone = node['bcpc']['floating']['reverse_dns_zone'] || calc_reverse_dns_zone(node['bcpc']['floating']['cidr'])

            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = \"#{node['bcpc']['dbname']['pdns']}\" AND TABLE_NAME=\"domains_static\"' | grep -q \"domains_static\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                    CREATE TABLE IF NOT EXISTS domains_static (
                        id INT auto_increment,
                        name VARCHAR(255) NOT NULL,
                        master VARCHAR(128) DEFAULT NULL,
                        last_check INT DEFAULT NULL,
                        type VARCHAR(6) NOT NULL,
                        notified_serial INT DEFAULT NULL,
                        account VARCHAR(40) DEFAULT NULL,
                        primary key (id)
                    );
                    INSERT INTO domains_static (name, type) values ('#{node['bcpc']['domain_name']}', 'NATIVE');
                    INSERT INTO domains_static (name, type) values ('#{reverse_dns_zone}', 'NATIVE');
                    CREATE UNIQUE INDEX dom_name_index ON domains_static(name);
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end

    ruby_block "powerdns-table-records" do
        block do

            reverse_dns_zone = node['bcpc']['floating']['reverse_dns_zone'] || calc_reverse_dns_zone(node['bcpc']['floating']['cidr'])

            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = \"#{node['bcpc']['dbname']['pdns']}\" AND TABLE_NAME=\"records_static\"' | grep -q \"records_static\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                        CREATE TABLE IF NOT EXISTS records_static (
                            id INT auto_increment,
                            domain_id INT DEFAULT NULL,
                            name VARCHAR(255) DEFAULT NULL,
                            type VARCHAR(6) DEFAULT NULL,
                            content VARCHAR(255) DEFAULT NULL,
                            ttl INT DEFAULT NULL,
                            prio INT DEFAULT NULL,
                            change_date INT DEFAULT NULL,
                            primary key(id)
                        );
                        INSERT INTO records_static (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains_static WHERE name='#{node['bcpc']['domain_name']}'),'#{node['bcpc']['domain_name']}','#{node['bcpc']['management']['vip']}','NS',300,NULL);
                        INSERT INTO records_static (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains_static WHERE name='#{node['bcpc']['domain_name']}'),'#{node['bcpc']['domain_name']}','#{node['bcpc']['management']['vip']}','A',300,NULL);
                        
                        INSERT INTO records_static (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains_static WHERE name='#{reverse_dns_zone}'),'#{reverse_dns_zone}','#{node['bcpc']['management']['vip']}','NS',300,NULL);
                        
                        CREATE INDEX rec_name_index ON records_static(name);
                        CREATE INDEX nametype_index ON records_static(name,type);
                        CREATE INDEX domain_id ON records_static(domain_id);
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end

    ruby_block "powerdns-function-dns-name" do
        block do
            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT name FROM mysql.proc WHERE name = \"dns_name\" AND db = \"#{node['bcpc']['dbname']['pdns']}\";' \"#{node['bcpc']['dbname']['pdns']}\" | grep -q \"dns_name\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                    delimiter //
                    CREATE FUNCTION dns_name (tenant VARCHAR(64) CHARACTER SET latin1) RETURNS VARCHAR(64)
                    COMMENT 'Returns the project name in a DNS acceptable format. Roughly RFC 1035.'
                    DETERMINISTIC
                    BEGIN
                      SELECT LOWER(tenant) INTO tenant;
                      SELECT REPLACE(tenant, '&', 'and') INTO tenant;
                      SELECT REPLACE(tenant, '_', '-') INTO tenant;
                      SELECT REPLACE(tenant, ' ', '-') INTO tenant;
                      SELECT REPLACE(tenant, '.', '-') INTO tenant;
                      RETURN tenant;
                    END//
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end

    ruby_block "powerdns-function-ip4_to_ptr_name" do
        block do
            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT name FROM mysql.proc WHERE name = \"ip4_to_ptr_name\" AND db = \"#{node['bcpc']['dbname']['pdns']}\";' \"#{node['bcpc']['dbname']['pdns']}\" | grep -q \"ip4_to_ptr_name\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                    delimiter //
                    CREATE FUNCTION ip4_to_ptr_name(ip4 VARCHAR(64) CHARACTER SET latin1) RETURNS VARCHAR(64)
                    COMMENT 'Returns the reversed IP with .in-addr.arpa appended, suitable for use in the name column of PTR records.'
                    DETERMINISTIC
                    BEGIN

                    return concat_ws( '.',  SUBSTRING_INDEX( SUBSTRING_INDEX(ip4, '.', 4), '.', -1),
                                            SUBSTRING_INDEX( SUBSTRING_INDEX(ip4, '.', 3), '.', -1),
                                            SUBSTRING_INDEX( SUBSTRING_INDEX(ip4, '.', 2), '.', -1),
                                            SUBSTRING_INDEX( SUBSTRING_INDEX(ip4, '.', 1), '.', -1), 'in-addr.arpa');

                    END//
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end

    ruby_block "powerdns-table-domains-view" do
        block do
            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = \"#{node['bcpc']['dbname']['pdns']}\" AND TABLE_NAME=\"domains\"' | grep -q \"domains\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                    CREATE OR REPLACE VIEW domains AS
                        SELECT id,name,master,last_check,type,notified_serial,account FROM domains_static UNION
                        SELECT
                            # rank each project to create an ID and add the maximum ID from the static table
                            (SELECT COUNT(*) FROM keystone_project WHERE y.id <= id) + (SELECT MAX(id) FROM domains_static) AS id,
                            CONCAT(CONCAT(dns_name(y.name), '.'),'#{node['bcpc']['domain_name']}') AS name,
                            NULL AS master,
                            NULL AS last_check,
                            'NATIVE' AS type,
                            NULL AS notified_serial,
                            NULL AS account
                            FROM keystone_project y;
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end

    ruby_block "powerdns-table-records" do
        block do
            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT table_name FROM INFORMATION_SCHEMA.TABLES WHERE table_name = \"records\" AND table_schema = \"#{node['bcpc']['dbname']['pdns']}\";' \"#{node['bcpc']['dbname']['pdns']}\" | grep -q \"records\""
            if not $?.success? then

                # Using this as a guide: http://doc.powerdns.com/html/generic-mypgsql-backends.html
                # We don't currently have all the fields in the table, but it doesn't seem to cause a problem so
                # far. I'm not changing the schema we have now. These might be important if we upgrade PDNS or
                # need to use other features.

                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                  create table records( 
                    id          bigint(20) not null default 0,
                    domain_id   bigint(20),
                    name        varchar(341),
                    type        varchar(6),
                    content     varchar(341),
                    ttl         bigint(20),
                    prio        int(11),
                    change_date bigint unsigned
                  );
                  
                  /* Use the indexes from the doc. */
                  CREATE INDEX nametype_index ON records(name,type);
                  CREATE INDEX domain_id ON records(domain_id);

                ]
            end
        end
    end

    get_all_nodes.each do |server|
        ruby_block "create-dns-entry-#{server['hostname']}" do
            block do
                system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records_static' | grep -q \"#{server['hostname']}.#{node['bcpc']['domain_name']}\""
                if not $?.success? then
                    %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                            INSERT INTO records_static (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{server['hostname']}.#{node['bcpc']['domain_name']}','#{server['bcpc']['management']['ip']}','A',300,NULL);
                    ]
                end
            end
        end

        ruby_block "create-dns-entry-#{server['hostname']}-shared" do
            block do
                system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records_static' | grep -q \"#{server['hostname']}-shared.#{node['bcpc']['domain_name']}\""
                if not $?.success? then
                    %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                            INSERT INTO records_static (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{server['hostname']}-shared.#{node['bcpc']['domain_name']}','#{server['bcpc']['floating']['ip']}','A',300,NULL);
                    ]
                end
            end
        end
    end

    %w{openstack zabbix}.each do |static|
        ruby_block "create-management-dns-entry-#{static}" do
            block do
                system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records_static' | grep -q \"#{static}.#{node['bcpc']['domain_name']}\""
                if not $?.success? then
                    %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                            INSERT INTO records_static (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{static}.#{node['bcpc']['domain_name']}','#{node['bcpc']['management']['vip']}','A',300,NULL);
                    ]
                end
            end
        end
    end

    %w{graphite kibana}.each do |static|
        ruby_block "create-monitoring-dns-entry-#{static}" do
            block do
                system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records_static' | grep -q \"#{static}.#{node['bcpc']['domain_name']}\""
                if not $?.success? then
                    %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                            INSERT INTO records_static (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{static}.#{node['bcpc']['domain_name']}','#{node['bcpc']['management']['monitoring']['vip']}','A',300,NULL);
                    ]
                end
            end
        end
    end

    %w{s3}.each do |static|
        ruby_block "create-floating-dns-entry-#{static}" do
            block do
                system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records_static' | grep -q \"#{static}.#{node['bcpc']['domain_name']}\""
                if not $?.success? then
                    %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                            INSERT INTO records_static (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{static}.#{node['bcpc']['domain_name']}','#{node['bcpc']['floating']['vip']}','A',300,NULL);
                            INSERT INTO records_static (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node[:bcpc][:domain_name]}'),'*.#{static}.#{node[:bcpc][:domain_name]}','#{static}.#{node[:bcpc][:domain_name]}','CNAME',300,NULL);
                    ]
                end
            end
        end
    end

    template "/etc/powerdns/pdns.d/pdns.local.gmysql" do
        source "pdns.local.gmysql.erb"
        owner "pdns"
        group "root"
        mode 00640
        notifies :restart, "service[pdns]", :immediately
    end

    service "pdns" do
        action [:enable, :start]
    end

end
