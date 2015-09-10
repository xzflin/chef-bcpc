#!/usr/bin/env python

from bcpc.openstack import credentials
from keystoneclient.v2_0 import client as ksclient
from novaclient.v2 import client as nclient
from time import sleep
import sys


def load_bash_env_file(filename):
    """This ill-advised method will load a bash environment file and process it as if
    where interpreted by the shell. In actual fact, that is all that it does:
    launches a shell with an empty environment then loads the file and enumerates
    the the new environment"""
    ## This is silly, because it implies that you would first have to detect the
    ## filetype... use shebang maybe?
    from subprocess import check_output
    envvars = check_output(['/usr/bin/env', '-', 'BASH_ENV=%s' % filename,
                            '/bin/bash', '-c', '/usr/bin/env'])
    envmap = {}
    for line in envvars.split('\n'):
        if len(line) == 0:
            continue
        k, v = line.split('=')
        envmap[k] = v
    return envmap

def create_tenant(ks=None):
    if ks is None:
        return None
    # Create the tenancy
    project = ks.tenants.create(**tenant_info)
    # Create the user, role, and associate
    user_info = {u'name': u'someuser',
                 u'password': u'foobar',
                 u'tenant_id': unicode(project.id),
                 u'email': u'someuser@email.com',
                 u'enabled': True}

    user = ks.users.create(**user_info)
    print project.list_users()


if __name__ == '__main__':
    import os
    env = load_bash_env_file(os.sep.join([os.environ['HOME'], 'adminrc']))
    os.environ.update(env)

    tenant_info = {u'tenant_name': u'my-project',
                   u'description': '',
                   u'enabled': True}

    ks = ksclient.Client(**credentials.get_keystone_creds())

    # Authenticate as the user and launch instance
    nc = nclient.Client(**credentials.get_nova_creds())
    params = {u'minDisk': 0, u'minRam': 0}
    img = nc.images.find(**params)
#    pp.pprint(img)
#    for img in nc.images.list():
#        pp.pprint(img.__dict__)
    flavor = nc.flavors.find(name=u'm1.tiny')
    instance_params = {u'name': u'test',
                    u'image': img,
                    u'flavor': flavor}
    instance = nc.servers.create(**instance_params)
    import pprint
    pp = pprint.PrettyPrinter(indent=2)

    status = instance.status
    while status == 'BUILD':
        sleep(5)
        instance = nc.servers.get(instance.id)
        status = instance.status
    if status != 'ACTIVE':
        print>>sys.stderr,'Something went wrong with instance %s' % instance.id
        sys.exit(-1)
    pp.pprint(instance.__dict__)
