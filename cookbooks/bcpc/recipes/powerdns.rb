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
    require 'ipaddr'

    include_recipe "bcpc::nova-head"

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

    cookbook_file "populate_dns.py" do
        action :create_if_missing
        mode 0755
        path "/usr/local/bin/populate_dns.py"
        owner "root"
        group "root"
        source "populate_dns.py"
    end

    template "/etc/powerdns/pdns.conf" do
        source "pdns.conf.erb"
        owner "root"
        group "root"
        mode 00600
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


    ruby_block "powerdns-table-domains" do
        block do

            reverse_fixed_zone = node['bcpc']['fixed']['reverse_dns_zone'] || calc_reverse_dns_zone(node['bcpc']['fixed']['cidr'])
            reverse_float_zone = node['bcpc']['floating']['reverse_dns_zone'] || calc_reverse_dns_zone(node['bcpc']['floating']['cidr'])

            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = \"#{node['bcpc']['dbname']['pdns']}\" AND TABLE_NAME=\"domains\"' | grep -q \"domains\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                    CREATE TABLE IF NOT EXISTS domains (
                        id INT auto_increment,
                        name VARCHAR(255) NOT NULL,
                        master VARCHAR(128) DEFAULT NULL,
                        last_check INT DEFAULT NULL,
                        type VARCHAR(6) NOT NULL,
                        notified_serial INT DEFAULT NULL,
                        account VARCHAR(40) DEFAULT NULL,
                        primary key (id)
                    );
                    INSERT INTO domains (name, type) values ('#{node['bcpc']['domain_name']}', 'NATIVE');
                    INSERT INTO domains (name, type) values ('#{reverse_float_zone}', 'NATIVE');
                    INSERT INTO domains (name, type) values ('#{reverse_fixed_zone}', 'NATIVE');
                    CREATE UNIQUE INDEX dom_name_index ON domains(name);
                    
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end

    ruby_block "powerdns-table-records" do
        block do
            reverse_fixed_zone = node['bcpc']['fixed']['reverse_dns_zone'] || calc_reverse_dns_zone(node['bcpc']['fixed']['cidr'])
            reverse_float_zone = node['bcpc']['floating']['reverse_dns_zone'] || calc_reverse_dns_zone(node['bcpc']['floating']['cidr'])

            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.TABLES WHERE TABLE_SCHEMA = \"#{node['bcpc']['dbname']['pdns']}\" AND TABLE_NAME=\"records\"' | grep -q \"records\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                        CREATE TABLE IF NOT EXISTS records (
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
                        INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{node['bcpc']['domain_name']}','#{node['bcpc']['management']['vip']}','NS',300,NULL);
                        INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{node['bcpc']['domain_name']}','#{node['bcpc']['management']['vip']}','A',300,NULL);
                        
                        INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{reverse_float_zone}'),'#{reverse_float_zone}','#{node['bcpc']['management']['vip']}','NS',300,NULL);
                        INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{reverse_fixed_zone}'),'#{reverse_fixed_zone}','#{node['bcpc']['management']['vip']}','NS',300,NULL);

                        INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{node['bcpc']['domain_name']}','#{node['bcpc']['domain_name']} root.#{node['bcpc']['domain_name']} #{Time.now.to_i}','SOA',300,NULL);

                        INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{reverse_float_zone}'),'#{reverse_float_zone}','#{node['bcpc']['domain_name']} root.#{node['bcpc']['domain_name']} #{Time.now.to_i}','SOA',300,NULL);

                        INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{reverse_fixed_zone}'),'#{reverse_fixed_zone}','#{node['bcpc']['domain_name']} root.#{node['bcpc']['domain_name']} #{Time.now.to_i}','SOA',300,NULL);
   
                        CREATE INDEX rec_name_index ON records(name);
                        CREATE INDEX nametype_index ON records(name,type);
                        CREATE INDEX domain_id ON records(domain_id);
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end


    get_all_nodes.each do |server|
        ruby_block "create-dns-entry-#{server['hostname']}" do
            block do
                system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records' | grep -q \"#{server['hostname']}.#{node['bcpc']['domain_name']}\""
                if not $?.success? then
                    %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                            INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{server['hostname']}.#{node['bcpc']['domain_name']}','#{server['bcpc']['management']['ip']}','A',300,NULL);
                    
                ]
                end
            end
        end

        ruby_block "create-dns-entry-#{server['hostname']}-shared" do
            block do
                system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records' | grep -q \"#{server['hostname']}-shared.#{node['bcpc']['domain_name']}\""
                if not $?.success? then
                    %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                            INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{server['hostname']}-shared.#{node['bcpc']['domain_name']}','#{server['bcpc']['floating']['ip']}','A',300,NULL);
                
                ]
                end
            end
        end
    end

    %w{openstack kibana graphite zabbix}.each do |static|
        ruby_block "create-management-dns-entry-#{static}" do
            block do
                system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records' | grep -q \"#{static}.#{node['bcpc']['domain_name']}\""
                if not $?.success? then
                    %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                            INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{static}.#{node['bcpc']['domain_name']}','#{node['bcpc']['management']['vip']}','A',300,NULL);
                
                ]
                end
            end
        end
    end

    %w{s3}.each do |static|
        ruby_block "create-floating-dns-entry-#{static}" do
            block do
                system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records' | grep -q \"#{static}.#{node['bcpc']['domain_name']}\""
                if not $?.success? then
                    %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                            INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{static}.#{node['bcpc']['domain_name']}','#{node['bcpc']['floating']['vip']}','A',300,NULL);
                    
                ]
                end
            end
        end
    end

    ruby_block "add-float-ips" do
    action :nothing
    block do
      reverse_dns_zone = node['bcpc']['floating']['reverse_dns_zone'] || calc_reverse_dns_zone(node['bcpc']['floating']['cidr'])
      float_cidr = IPAddr.new(node['bcpc']['floating']['available_subnet'])
      float_cidr.to_range().each do |ip|
        hostname = "public-" + ip.to_s().gsub(".", "-") + "." + node['bcpc']['domain_name']
        reverse_name = ip.reverse()
        system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records' | grep -q \"#{hostname}\""
        if not $?.success? then
          %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
             INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}'),'#{hostname}','#{ip.to_s()}','A',300,NULL);
                
            ]
        end
        system "mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} -e 'SELECT name FROM records' | grep -q \"#{reverse_name}\""
        if not $?.success? then
          %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
             INSERT INTO records (domain_id, name, content, type, ttl, prio) VALUES ((SELECT id FROM domains WHERE name='#{reverse_dns_zone}'),'#{reverse_name}','#{hostname}','PTR',300,NULL);
            ]
        end                
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
            end
        end
    end

  ruby_block "add-fixed-ips" do
    block do
      system "mysql -N -B -u root -pW2x42JNYBdeaQ6gDCA0Y -e 'select (select count(*) from nova.fixed_ips) - (select count(*) from pdns.records where name like \"ip-%\" and type=\"A\") as diff;' | egrep \"^0$\"" 
      if not $?.success? then     
        reverse_dns_zone = node['bcpc']['fixed']['reverse_dns_zone'] || calc_reverse_dns_zone(node['bcpc']['fixed']['cidr'])
        pwd = get_config('mysql-root-password')
     
        %x[ mysql -uroot -p#{pwd} #{node['bcpc']['dbname']['pdns']} <<-EOH
             DELETE from records where name like "ip-%" and type="A";
             INSERT INTO records (domain_id, name, content, type, ttl, prio) select (SELECT id FROM domains WHERE name='#{node['bcpc']['domain_name']}') , concat("ip-", replace(address, ".", "-"), ".#{node['bcpc']['domain_name']}"), address ,'A',300,NULL from nova.fixed_ips;
             DELETE from records where content like "ip-%" and type="PTR";
             INSERT INTO records (domain_id, name, content, type, ttl, prio) select (SELECT id FROM domains WHERE name='#{reverse_dns_zone}') , ip4_to_ptr_name(address) ,  concat("ip-", replace(address, ".", "-"), ".#{node['bcpc']['domain_name']}"),'PTR',300,NULL from nova.fixed_ips;       
        ] 
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

  template "/usr/local/etc/dns_fill.yml" do
    source "pdns.dns_fill.yml.erb"
    owner "pdns"
    group "root"
    mode 00640    
  end

  cookbook_file "/usr/local/bin/dns_fill.py" do
    source "dns_fill.py"
    mode "00755"
    owner "pdns"
    group "root"
  end

  cron "run dns_fill" do
    minute "*/5"
    hour "*"
    weekday "*"
    command "/usr/local/bin/if_vip /usr/local/bin/dns_fill.py -c /usr/local/etc/dns_fill.yml run"
  end


  
end
