#!/usr/bin/env python

"""
Converts between cluster.txt and cluster.yaml. cluster.yaml carries more
information than cluster.txt, so converting from cluster.yaml to cluster.txt
will discard information.

cluster.yaml schema example:

cluster_name: TEST
nodes:
  fake-node-r06n01:
    domain: completelyfake.example
    hardware_type: null
    ip_address: 131.81.229.220
    ipmi_address: 62.185.178.18
    mac_address: 21:b0:d5:9b:f8:3b
    role: bootstrap
  [...]
    fake-node-r06n02:
    domain: completelyfake.example
    hardware_type: null
    ip_address: 127.228.36.77
    ipmi_address: 218.161.198.210
    mac_address: 18:c2:93:42:a5:cd
    role: work
"""

import argparse
import os
import sys
import yaml


def merge(a, b, path=[]):
    """ merges b into a
    http://stackoverflow.com/questions/7204805/dictionaries-of-dictionaries-merge/7205107#7205107
    """
    for key in b:
        if key in a:
            if isinstance(a[key], dict) and isinstance(b[key], dict):
                merge(a[key], b[key], path + [str(key)])
            elif a[key] == b[key]:
                pass
        else:
            a[key] = b[key]
    return a


def load_existing_yaml(file_list):
    out = {}
    for infile in file_list:
        with open(infile) as f:
            merge(out, yaml.safe_load(f))
    return out


def to_yaml(path=None, cluster_name=None, existing=[]):
    """
    Opens and reads the given file, which is assumed to be in cluster.txt
    format. Returns a string with cluster.txt converted to YAML, or dies
    trying.
    """
    f = open(path)
    cluster_txt = f.readlines()
    f.close()

    cluster = {'cluster_name': cluster_name, 'nodes': {}}

    e_yaml = {'cluster_name': cluster_name, 'nodes': {}}
    if len(existing) > 0:
        e_yaml.update(load_existing_yaml(existing))

    for line in cluster_txt:
        if line.strip() == "end":
            break
        try:
            name, mac, ip, ipmi, domain, role = line.strip().split()
        except ValueError, e:
            err = "ERROR: failure unpacking line '%s' into 6 values: %s. "
            err += "Is this a valid cluster.txt file? Exiting."
            sys.exit(err % (line.strip(), e))
        if name in cluster['nodes']:
            sys.exit("ERROR: %s found more than once in cluster.txt" % name)
        if ipmi == "-":
            ipmi = None
        cluster['nodes'][name] = {'mac_address': mac,
                                  'ip_address': ip,
                                  'ipmi_address': ipmi,
                                  'domain': domain,
                                  'role': role}

        merge(e_yaml['nodes'], cluster['nodes'])
        if 'hardware_type' not in e_yaml['nodes'][name]:
            e_yaml['nodes'][name]['hardware_type'] = None

    return yaml.dump(e_yaml, default_flow_style=False)


def to_text(path):
    """
    Opens and reads the given file, which is assumed to be YAML.
    Returns a string with cluster.yaml converted to text, or dies trying.
    """
    f = open(path)
    cluster_yaml = f.read()
    f.close()

    cluster = yaml.safe_load(cluster_yaml)
    # if it's a string and not a dict, something not YAML was loaded
    if type(cluster) != dict:
        sys.exit("ERROR: %s did not parse as YAML. Exiting." % path)

    buf = ""

    for node in sorted(cluster['nodes'].keys()):
        if cluster['nodes'][node]['ipmi_address'] is None:
            ipmi_address = "-"
        else:
            ipmi_address = cluster['nodes'][node]['ipmi_address']

        line = "%s %s %s %s %s %s\n" % (
            node,
            cluster['nodes'][node]['mac_address'],
            cluster['nodes'][node]['ip_address'],
            ipmi_address,
            cluster['nodes'][node]['domain'],
            cluster['nodes'][node]['role']
        )
        buf += line

    buf += "end"
    return buf


def main():
    parser = argparse.ArgumentParser(
        description='Converts between cluster.txt and cluster.yaml. '
        'Text to YAML is the default direction. Specify -t to go from '
        'YAML to text. The YAML format contains more information than '
        'the text format, so information will be lost when converting '
        'to text.')
    parser.add_argument("path", help="path to cluster.txt")
    parser.add_argument("cluster_name", help="name of cluster")
    parser.add_argument("-e", "--existing",
                        help="path to existing cluster.yml file."
                        " Can be used multiple times. Values from each"
                        " successive file take precedence over those"
                        " specified earlier.",
                        action='append', default=[])
    parser.add_argument("-t", "--text",
                        help="convert from YAML to text"
                        " (THIS WILL DISCARD DATA)",
                        action="store_true")
    args = parser.parse_args()

    for path in ([args.path] + args.existing):
        if not os.path.exists(path) or not os.access(path, os.R_OK):
            sys.exit("ERROR: Unable to open %s" % args.path)

    if args.text:
        # Ignore existing here
        print(to_text(args.path))
    else:
        print(to_yaml(args.path, args.cluster_name, args.existing))


if __name__ == "__main__":
    main()
