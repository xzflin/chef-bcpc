#
# Cookbook Name:: bcpc
# Provider:: cephconfig
#
# Copyright 2015, Bloomberg Finance L.P.
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

def whyrun_supported?
  true
end

action :set do
  unless ::Dir.exists?(@new_resource.path)
    Chef::Log.info("Ceph directory \"#{@new_resource.path}\" doesn't exist!")
    next
  end

  sockets = ::Dir.glob(::File.join(@new_resource.path, @new_resource.target) + ".asok").select do |file|
    ::File.socket? file
  end

  sockets.each do |socket_path|
    cmd = Mixlib::ShellOut.new("ceph daemon #{socket_path} config get #{@new_resource.name}").run_command
    begin
      m = JSON.parse(cmd.stdout)
    rescue JSON::ParserError
      raise "Command output is not JSON: #{cmd.stdout} | #{cmd.stderr}"
    end

    converge_needed = m.has_key?(@new_resource.name) ? (m[@new_resource.name] != @new_resource.value) : false
    next unless converge_needed

    converge_by("Setting ceph config on #{socket_path}") do
      set_cmd = Mixlib::ShellOut.new("ceph daemon #{socket_path} config set #{@new_resource.name} #{@new_resource.value}").run_command
      if set_cmd.stdout.include?("\"success\"")
        Chef::Log.info("Ceph target \"#{socket_path}\" set #{@new_resource.name}:#{@new_resource.value}")
      else
        e = "Ceph target \"#{socket_path}\" unable to set #{@new_resource.name}:#{@new_resource.value}: #{set_cmd.stdout}"
        Chef::Log.error e
        raise e
      end
    end
  end
end
