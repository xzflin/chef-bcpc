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

    include_recipe "bcpc::nova-head"

    cookbook_file "populate_dns.py" do
        action :create_if_missing
        mode 0755
        path "/usr/local/bin/populate_dns.py"
        owner "root"
        group "root"
        source "populate_dns.py"
    end

    template "/usr/local/bin/populate_dns.py.wrapper" do
        source "populate_dns.py.wrapper.erb"
        owner "root"
        group "root"
        mode 00700
    end

    ruby_block "powerdns-table-records_forward-view" do
        block do
            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = \"#{node['bcpc']['dbname']['pdns']}\" AND TABLE_NAME=\"records_forward\"' | grep -q \"records_forward\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                    CREATE OR REPLACE VIEW records_forward AS
                        /* SOA Forward */
                        select -1 as id ,
                            (SELECT id FROM domains_static WHERE name='#{node['bcpc']['domain_name']}') as domain_id,
                            '#{node['bcpc']['domain_name']}' as name,
                            'SOA' as type,
                            concat('#{node['bcpc']['domain_name']} root.#{node['bcpc']['domain_name']} ', (select cast(unix_timestamp(greatest(coalesce(max(created_at), 0), coalesce(max(updated_at), 0), coalesce(max(deleted_at), 0))) as unsigned integer) from nova.floating_ips) ) as content,
                             300 as ttl, NULL as prio,
                             NULL as change_date
                        union
                        SELECT id,domain_id,name,type,content,ttl,prio,change_date FROM records_static UNION  
                        # assume we only have 500 or less static records
                        SELECT domains.id+500 AS id, domains.id AS domain_id, domains.name AS name, 'NS' AS type, '#{node['bcpc']['management']['vip']}' AS content, 300 AS ttl, NULL AS prio, NULL AS change_date FROM domains WHERE id > (SELECT MAX(id) FROM domains_static) UNION
                        # assume we only have 250 or less static domains
                        SELECT domains.id+750 AS id, domains.id AS domain_id, domains.name AS name, 'SOA' AS type, concat('#{node['bcpc']['domain_name']} root.#{node['bcpc']['domain_name']} ', (select cast(unix_timestamp(greatest(coalesce(max(created_at), 0), coalesce(max(updated_at), 0), coalesce(max(deleted_at), 0))) as unsigned integer) from nova.floating_ips) ) AS content, 300 AS ttl, NULL AS prio, NULL AS change_date FROM domains WHERE id > (SELECT MAX(id) FROM domains_static) UNION
                        # again, assume we only have 250 or less static domains
                        SELECT nova.instances.id+10000 AS id,
                            # query the domain ID from the domains view
                            (SELECT id FROM domains WHERE name=CONCAT(CONCAT((SELECT dns_name(name) FROM keystone_project WHERE id = nova.instances.project_id),
                                                                      '.'),'#{node['bcpc']['domain_name']}')) AS domain_id,
                            # create the FQDN of the record
                            CONCAT(nova.instances.hostname,
                              CONCAT('.',
                                CONCAT((SELECT dns_name(name) FROM keystone_project WHERE id = nova.instances.project_id),
                                  CONCAT('.','#{node['bcpc']['domain_name']}')))) AS name,
                            'A' AS type,
                            nova.floating_ips.address AS content,
                            300 AS ttl,
                            NULL AS prio,
                            NULL AS change_date FROM nova.instances, nova.fixed_ips, nova.floating_ips
                            WHERE nova.instances.uuid = nova.fixed_ips.instance_uuid AND nova.floating_ips.fixed_ip_id = nova.fixed_ips.id;
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end

    ruby_block "powerdns-table-records_reverse-view" do
        block do

            reverse_dns_zone = node['bcpc']['floating']['reverse_dns_zone'] || calc_reverse_dns_zone(node['bcpc']['floating']['cidr'])

            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = \"#{node['bcpc']['dbname']['pdns']}\" AND TABLE_NAME=\"records_reverse\"' | grep -q \"records_reverse\""
            if not $?.success? then

                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                    create or replace view records_reverse as
                    /* SOA reverse */
                    select -2 as id,
                        (SELECT id FROM domains_static WHERE name='#{reverse_dns_zone}') as domain_id,
                        '#{reverse_dns_zone}' as name, 
                        'SOA' as type,
                        concat('#{node['bcpc']['domain_name']} root.#{node['bcpc']['domain_name']} ', (select cast(unix_timestamp(greatest(coalesce(max(created_at), 0), coalesce(max(updated_at), 0), coalesce(max(deleted_at), 0))) as unsigned integer) from nova.floating_ips) ) as content,
                        300 as ttl, NULL as prio,
                        NULL as change_date
                    union all
                    select r.id * -1 as id, d.id as domain_id,
                          ip4_to_ptr_name(r.content) as name,
                          'PTR' as type, r.name as content, r.ttl, r.prio, r.change_date
                    from records_forward r, domains d
                    where r.type='A' 
                      and d.name = '#{reverse_dns_zone}'
                      and ip4_to_ptr_name(r.content) like '%.#{reverse_dns_zone}';

                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references

            end
        end
    end


    ruby_block "powerdns-table-records-all-view" do

        block do
            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT TABLE_NAME FROM INFORMATION_SCHEMA.VIEWS WHERE TABLE_SCHEMA = \"#{node['bcpc']['dbname']['pdns']}\" AND TABLE_NAME=\"records_all\"' | grep -q \"records_all\""
            if not $?.success? then

                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                  create or replace view records_all as
                    select id, domain_id, name, type, content, ttl, prio, change_date from records_forward
                    union all
                    select id, domain_id, name, type, content, ttl, prio, change_date from records_reverse;
                ]

                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end

        end

    end

    ruby_block "powerdns-function-populate_records" do
        block do
            system "mysql -uroot -p#{get_config('mysql-root-password')} -e 'SELECT name FROM mysql.proc WHERE name = \"populate_records\" AND db = \"#{node['bcpc']['dbname']['pdns']}\";' \"#{node['bcpc']['dbname']['pdns']}\" | grep -q \"populate_records\""
            if not $?.success? then
                %x[ mysql -uroot -p#{get_config('mysql-root-password')} #{node['bcpc']['dbname']['pdns']} <<-EOH
                    delimiter //
                    CREATE PROCEDURE populate_records () 
                    COMMENT 'Persists dynamic DNS records from records_all view into records table'
                    BEGIN

                        start transaction;
                            delete from records;
                            insert into records(id, domain_id, name, type, content, ttl, prio, change_date)
                            select id, domain_id, name, type, content, ttl, prio, change_date
                            from records_all;
                        commit;

                    END//
                ]
                self.notifies :restart, "service[pdns]", :delayed
                self.resolve_notification_references
            end
        end
    end

    cron "powerdns_populate_records" do
        minute "*"
        hour "*"
        weekday "*"
        command "/usr/local/bin/populate_dns.py.wrapper"
    end

end
