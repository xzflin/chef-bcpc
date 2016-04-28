#
# Cookbook Name:: bcpc
# Recipe:: federated-kerberos
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
    
# install the apache mod
package "libapache2-mod-auth-kerb" do
    action :upgrade
end

# drop the sso template into place
cookbook_file "/etc/keystone/sso_callback_template.html" do
    owner "root"
    group "root"
    mode "0644"
    source "keystone/sso_callback_template.html"
end
