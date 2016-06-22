
# Cookbook Name:: bcpc
# Provider:: zbx_autoreg
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

def whyrun_supported?
  true
end

action :create do
  auth = zbx_auth
  # Checks for existence of auto-registration action
  params = {
    :name => @new_resource.name + ' auto registration'
  }

  if zbx_api(auth, 'action.exists', params) == false
    Chef::Log.info("Action #{@new_resource.name} does not exist")

    # Determine if template exists
    params = {
      :filter => {
        :host => @new_resource.template
      }
    }
    result = zbx_api(auth, 'template.get', params)
    raise "Template #{@new_resource.template} does not exist" if result.length < 1

    templates = []
    result.map{ |t| templates.push({ :templateid => t['templateid'] }) }

    # Determine if hostgroup exists
    params = {
      :filter => {
        :name => @new_resource.hostgroup
      }
    }
    result = zbx_api(auth, 'hostgroup.get', params)
    raise "Hostgroup #{@new_resource.hostgroup} does not exist" if result.length < 1

    hostgroups = []
    result.map{ |h| hostgroups.push({ :operationid => 1, :groupid => h['groupid'] }) }

    # If template and hostgroup exist, create registration action
    params = {
      :name => @new_resource.name + ' auto registration',
      :eventsource => 2,
      :status => 0,
      :esc_period => 0,
      :filter => {
        :evaltype => 0,
        :conditions => [
          {
            :conditiontype => 24,
            :operator => 2,
            :value => @new_resource.metadata
          }
        ]
      },
      :operations => [
        {
          :esc_step_from => 1,
          :esc_period => 0,
          :optemplate => templates,
          :operationtype => 6,
          :esc_step_to => 1
        },
        {
          :esc_step_from => 1,
          :esc_period => 0,
          :opgroup => hostgroups,
          :operationtype => 4,
          :esc_step_to => 1
        }
      ]
    }
    converge_by "create auto-registration action #{@new_resource.name}" do
      result = zbx_api(auth, 'action.create', params)
      raise "Unable to create action #{@new_resource.name}: #{result}" if result.nil?
    end
  end
end
