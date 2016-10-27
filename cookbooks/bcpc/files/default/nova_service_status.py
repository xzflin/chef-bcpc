#!/usr/bin/env python

import datetime
import json
import subprocess
import sys

def main():
    s = subprocess.Popen(
        ['openstack', 'compute', 'service', 'list', '-f', 'json'],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE)
    cmd_stdout, cmd_stderr = s.communicate()
    if s.returncode != 0:
        sys.exit("Failed to run openstack command: %s" % cmd_stderr)

    service_list = json.loads(cmd_stdout)

    # service dict has keys:
    # - Status (enabled/disabled)
    # - Binary (name of process)
    # - Zone (availability zone)
    # - Host
    # - State (up/down)
    # - Updated At
    down_services = [
       service for service in service_list
       if service['State'] != 'up' and service['Status'] == 'enabled']

    for down_service in down_services:
        utc_time = datetime.datetime.strptime(
            down_service['Updated At'],
            '%Y-%m-%dT%H:%M:%S.%f')

        print("{} down on {} at {}".format(
            down_service['Binary'],
            down_service['Host'],
            str(utc_time) + " UTC"))

if __name__ == '__main__':
    main()
