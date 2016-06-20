#!/usr/bin/env python
import argparse
import logging
import os
import shlex
import subprocess
import yaml


class CobblerEnroller(object):
    def __init__(self, cluster_yaml_path=None, dry_run=False):
        """
        A path to cluster.yaml/cluster.yml may be specified here.
        If None, the constructor will invoke self.find_cluster_yaml().
        If a valid YAML file is found

        :param cluster_yaml_path: string path to cluster.yaml
        """
        self.dry_run = dry_run

        if cluster_yaml_path is None:
            cluster_yaml_path = self.find_cluster_yaml()

        self.nodes = self.load_cluster_yaml(cluster_yaml_path)['nodes']
        self.systems = self.get_cobbler_systems()
        self.distros = self.get_cobbler_distros()
        self.profiles = self.get_cobbler_profiles()

    def run(self, command, dry_run=False):
        """
        Convenience wrapper for subprocess.Popen. If self.dry_run is set,
        will just report the command that would have been executed.
        """
        if dry_run:
            logging.warning('Would execute %s' % command)
        else:
            logging.warning('Executing %s' % command)
            cmd = subprocess.Popen(
                shlex.split(command),
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE)
            cmd.wait()
            return cmd

    def find_cluster_yaml(self):
        """
        This method will walk the directory tree up to / looking for a file
        named cluster.yaml or cluster.yml (preferring the full .yaml
        extension). If it reaches / and cannot find a matching file there,
        it will raise a runtime error.
        """
        path = os.path.abspath(os.path.curdir)
        # the while condition here will be true if path is /
        # (no more elements can be peeled off)
        while path != os.path.dirname(path):
            dir_contents = os.listdir(path)
            for c_yaml in ['cluster.yaml', 'cluster.yml']:
                c_yaml_path = os.path.join(path, c_yaml)
                if (c_yaml in dir_contents and
                        self.is_valid_cluster_yaml(c_yaml_path)[0]):
                    if self.dry_run:
                        logging.warning(
                            'Found cluster YAML at %s' % c_yaml_path)
                    return c_yaml_path
            path = os.path.dirname(path)
        # no more directories to peel off, fell out of while
        raise RuntimeError("Could not locate cluster.yaml/.yml")

    def is_valid_cluster_yaml(self, yaml_to_load):
        """
        Scans the given YAML, or opens the file object given and loads it as
        YAML, and checks it to see if it matches an expected schema for the
        cluster YAML.

        :param yaml_to_load: either a string containing YAML or a file object
            pointing to a YAML file
        :returns: 2-tuple of (bool, list), where bool is True if valid YAML and
            False is not; if False, list will contain a list of strings
            explaining what checks failed
        """
        cluster_yaml_failed_checks = []

        if type(yaml_to_load) is file:
            cluster_yaml = yaml_to_load.read()
            yaml_to_load.close()
        else:
            cluster_yaml = yaml_to_load

        y = self.load_cluster_yaml(cluster_yaml)
        if y is None:
            return (False, ['empty_yaml_file'])

        if 'cluster_name' not in y:
            cluster_yaml_failed_checks += ['cluster_name_key_missing']

        if 'nodes' not in y:
            cluster_yaml_failed_checks += ['nodes_key_missing']
        else:
            node_keys = set([
                'cobbler_profile', 'domain', 'hardware_type',
                'ip_address', 'ipmi_address', 'ipmi_password',
                'ipmi_username', 'mac_address', 'role'])
            for node in y['nodes']:
                if set(y['nodes'][node].keys()) != node_keys:
                    cluster_yaml_failed_checks += ['%s_missing_keys' % node]

        if not len(cluster_yaml_failed_checks):
            return (True, [])
        else:
            logging.error('Checks failed: %s' % cluster_yaml_failed_checks)
            return (False, cluster_yaml_failed_checks)

    def load_cluster_yaml(self, path):
        """
        Loads the given path as YAML and returns the Python object
        corresponding to the YAML document.

        :param path: path to some YAML
        :returns: the loaded YAML as a Python object
        """
        with open(path) as f:
            return yaml.safe_load(f)

    def get_cobbler_systems(self):
        return self.run('cobbler system list').stdout.read().split()

    def get_cobbler_distros(self):
        return self.run('cobbler distro list').stdout.read().split()

    def get_cobbler_profiles(self):
        return self.run('cobbler profile list').stdout.read().split()

    def add_host(self, host):
        if host not in self.nodes:
            raise ValueError('node %s not in cluster.yml' % host)

        add_command = (
            'cobbler system add --name={name} '
            '--hostname={hostname}.{domain} '
            '--profile={profile} '
            '--ip-address={ip_address} '
            '--mac={mac} '
            '--interface=eth0').format(
                name=host,
                hostname=host,
                domain=self.nodes[host]['domain'],
                profile=self.nodes[host]['cobbler_profile'],
                ip_address=self.nodes[host]['ip_address'],
                mac=self.nodes[host]['mac_address'])
        # Cobbler will explode if the system is already present, so
        # don't try to re-add it
        if host in self.systems:
            logging.warning('%s already in Cobbler, skipping' % host)
        elif self.nodes[host]['role'] == 'bootstrap':
            logging.warning('%s has bootstrap role, skipping' % host)
        else:
            cobbler_add = self.run(add_command, self.dry_run)

            if cobbler_add is not None and cobbler_add.returncode != 0:
                raise RuntimeError(
                    'cobbler add returned %i: %s' %
                    (cobbler_add.returncode, cobbler_add.stdout.read()))

        self.sync_cobbler()

    def remove_host(self, host):
        if host not in self.systems:
            raise ValueError('node %s not known to Cobbler' % host)

        remove_command = 'cobbler system remove --name=%s' % host
        cobbler_remove = self.run(remove_command, self.dry_run)

        if cobbler_remove is not None and cobbler_remove.returncode != 0:
            raise RuntimeError(
                'cobbler remove returned %i: %s' %
                (cobbler_remove.returncode, cobbler_remove.stdout.read()))

        self.sync_cobbler()

    def add_all_hosts_in_role(self, role):
        valid_roles = set(self.nodes[node]['role'] for node in self.nodes)
        if role not in valid_roles:
            raise RuntimeError(
                '%s not in valid role list %s' %
                (role, '|'.join(valid_roles)))

        hosts_with_role = [node for node in self.nodes
                           if self.nodes[node]['role'] == role]

        for host in hosts_with_role:
            self.add_host(host)

    def add_all_hosts(self):
        for host in self.nodes:
            self.add_host(host)

    def sync_cobbler(self):
        sync = self.run('cobbler sync', self.dry_run)
        if sync is not None and sync.returncode != 0:
            raise RuntimeError(
                'cobbler sync returned %i: %s' %
                (sync.returncode, sync.stdout.read()))


def main():
    parser = argparse.ArgumentParser(description='Enroll nodes in Cobbler.')
    parser.add_argument(
        '-n', '--dry-run',
        help='Print commands to be executed but do not change configuration',
        action='store_true')
    parser.add_argument(
        'command', choices=['add_host', 'add_role', 'add_all', 'remove_host'],
        help='Command to execute')
    parser.add_argument(
        '-t', '--target',
        help='Host/role to operate on', default='')
    parser.add_argument(
        '-c', '--cluster-yaml',
        help='Path to cluster.yaml/yml; if not provided, will be searched for '
             'in each directory above this one.',
        default=None)
    args = parser.parse_args()

    cobb = CobblerEnroller(
        cluster_yaml_path=args.cluster_yaml,
        dry_run=args.dry_run)

    if args.command != 'add_all' and args.target == '':
        raise RuntimeError('need a target')

    if args.command == 'add_host':
        cobb.add_host(args.target)
    elif args.command == 'add_role':
        cobb.add_all_hosts_in_role(args.target)
    elif args.command == 'add_all':
        cobb.add_all_hosts()
    elif args.command == 'remove_host':
        cobb.remove_host(args.target)
    else:
        raise RuntimeError('invalid command: %s' % args.command)

if __name__ == '__main__':
    main()
