#!/usr/bin/env python

from bcpc.openstack import credentials
from keystoneclient.v2_0 import client as ksclient

#@hack
def load_bash_env_file(filename):
    """This ill-advised method will load a bash environment file and process it as if
    where interpreted by the shell. In actual fact, that is all that it does:
    launches a shell with an empty environment then loads the file and enumerates
    the the new environment"""
    ## This is silly, because it implies that you would first have to detect the
    ## filetype... use shebang maybe?
    from subprocess import check_output
    envvars = check_output(['/usr/bin/env','-','BASH_ENV=%s' % filename,
                        '/bin/bash', '-c','/usr/bin/env'])
    envmap = {}
    for line in envvars.split('\n'):
        if len(line) == 0: continue
        # TODO: Implement a logger!!!
        #print 'Spliting line %s' % line
        k, v = line.split('=')
        envmap[k] = v
    return envmap

if __name__ == '__main__':
    import os
    env = load_bash_env_file(os.sep.join([os.environ['HOME'],'adminrc']))
    os.environ.update(env)

    ks = ksclient.Client(**credentials.get_keystone_creds())
    print ks
