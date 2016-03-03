#!/usr/bin/env python

"""
Tool to compare user-defined cinder/nova quotas (yaml configuration generated
by Chef) with the in-effect limits and apply required changes for each project.

Running of tool requires administrator-level Openstack credentials to be set
via environment variables.
"""

import re
import string
import syslog
import subprocess
import yaml
import MySQLdb
import _mysql_exceptions

db_conf = '/etc/mysql/debian.cnf'
quota_conf = '/usr/local/etc/os-quota.yml'


class OSQuota(object):
    def __init__(self, config):
        self.db = MySQLdb.connect(read_default_file=db_conf)
        self.config = config

    # Retrieve project/tenant UUID
    def _get_tenant_id(self, project):
        uuid_re = re.compile('[0-9a-f]{32}\Z', re.I)
        c = self.db.cursor()
        c.execute("SELECT id FROM keystone.project WHERE name = %s",
                  (project,))
        tenant_id = c.fetchone()
        if tenant_id is not None and re.match(uuid_re, tenant_id[0]):
            return tenant_id[0]
        else:
            syslog.syslog(syslog.LOG_ERR, "Non-existent project defined: %s"
                          % project)
            raise Exception("Non-existent project defined: %s" % project)

    # Retrieve list of non-default quotas from database for the project
    def _get_current_quota(self, component, tenant_id):
        try:
            self.db.select_db(component)
        except _mysql_exceptions.Error as e:
            syslog.syslog(syslog.LOG_ERR, "Unexpected MySQL error %d: %s:"
                          % (e[0], e[1]))
            raise
        c = self.db.cursor()
        c.execute("SELECT resource, hard_limit FROM quotas WHERE "
                  "project_id = %s AND deleted = 0", (tenant_id,))
        current_quota = c.fetchall()
        return current_quota

    # Parse quota defined in yaml configuration
    def _parse_conf_quota(self, quota):
        configured_quota = []
        for resource, limit in quota.iteritems():
            configured_quota.append((resource, limit))
        return tuple(configured_quota)

    # Construct nova/cinder quota-update command
    def _construct_quota_cmd(self, component, quota, tenant_id):
        quota_cmd = [component, 'quota-update']
        # Validate provided component and resources for quota-update
        for (resource, limit) in quota:
            if component == 'nova':
                if resource not in ['instances', 'cores', 'ram',
                                    'floating_ips', 'fixed_ips',
                                    'metadata_items', 'injected_files',
                                    'injected_file_content_bytes',
                                    'injected_file_path_bytes',
                                    'key_pairs', 'security_groups',
                                    'security_group_rules', 'server_groups',
                                    'server_group_members']:
                    syslog.syslog(syslog.LOG_ERR, "No such nova resource: %s"
                                  % resource)
                    raise Exception("No such nova resource: %s" % resource)
            elif component == 'cinder':
                if resource not in ['volumes', 'snapshots', 'gigabytes']:
                    syslog.syslog(syslog.LOG_ERR, "No such cinder resource: %s"
                                  % resource)
                    raise Exception("No such cinder resource: %s" % resource)
            else:
                syslog.syslog(syslog.LOG_ERR, "Unrecognized component %s"
                              % component)
                raise Exception("Unrecognized component %s" % component)

            quota_cmd.append('--' + string.replace(resource, '_', '-'))
            quota_cmd.append(str(limit))

        # Force nova quota reductions regardless of current usage
        # Cinder quota reductions do not validate current usages by default
        if component == 'nova':
            quota_cmd.append('--force')
        quota_cmd.append(tenant_id)
        return quota_cmd

    def run(self):
        for component in config:
            for project in config[component]:
                tenant_id = self._get_tenant_id(project)
                current_quota = sorted(self._get_current_quota(component, tenant_id))
                conf_quota = sorted(self._parse_conf_quota(config[component][project]))
                # If defined quota does not match in-effect quota, apply update
                if cmp(current_quota, conf_quota) != 0:
                    quota_cmd = self._construct_quota_cmd(component,
                                                          conf_quota,
                                                          tenant_id)
                    process = subprocess.Popen(quota_cmd)
                    process.communicate()
                    if process.returncode != 0:
                        syslog.syslog(syslog.LOG_ERR, "Unable to update quota "
                                      "for %s: %s" % (project, str(quota_cmd)))
                        raise Exception("Unable to update quota: %s"
                                        % quota_cmd)
                    else:
                        syslog.syslog(syslog.LOG_INFO, "Updated %s quota for "
                                      "%s: %s" % (component, project,
                                                  str(conf_quota)))
        self.db.close()


if __name__ == '__main__':
    config = yaml.load(open(quota_conf, 'r'))
    quota = OSQuota(config).run()
