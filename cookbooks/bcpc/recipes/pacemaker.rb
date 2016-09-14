#
# Cookbook Name:: bcpc
# Recipe:: pacemaker-common
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

include_recipe "bcpc::default"

# this will install corosync, libqb0, crmsh dependencies
package "pacemaker" do
    action :upgrade
end

# corosync autostart

# corosync.conf

# iptables for corosync
# `update-rc.d pacemaker defaults 20 01`
# start corosync
# disable stonith
# start pacemaker
# pacemaker resources
# crm configure load update cluster-ip.conf
# pacemaker group?
# sudo crm configure load update cluster-ip.conf
# primitive nginx lsb:nginx op monitor interval="10s"
# primitive nginx-ip ocf:heartbeat:IPaddr2 params ip="192.168.56.105" cidr_netmask="24" op monitor interval="2s"
# group failover-nginx nginx-ip nginx


# sudo crm configure load update cluster-ip.conf
# https://www.suse.com/documentation/sle-ha-12/book_sleha/data/sec_ha_config_crm_resources.html
