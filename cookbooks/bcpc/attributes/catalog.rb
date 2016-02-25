###########################################
#
# Service catalog (API versions/endpoints)
#
###########################################

# see docs/installing_liberty.md for JSON for upgraded API versions
default['bcpc']['catalog'] = {
  'identity' => {
    'name' => 'keystone',
    'project' => 'keystone',
    'description' => 'OpenStack Identity',
    'ports' => {
      'admin' => 35357,
      'internal' => 5000,
      'public' => 5000
    },
    'uris' => {
      'admin' => 'v2.0',
      'internal' => 'v2.0',
      'public' => 'v2.0'
    }
  },
  # Nova endpoint notes for Liberty: v1.1 will _not work_, you must use a v2 endpoint
  'compute' => {
    'name' => 'Compute Service',
    'project' => 'nova',
    'description' => 'OpenStack Compute Service',
    'ports' => {
      'admin' => 8774,
      'internal' => 8774,
      'public' => 8774
    },
    'uris' => {
      'admin' => 'v1.1/%(tenant_id)s',
      'internal' => 'v1.1/%(tenant_id)s',
      'public' => 'v1.1/%(tenant_id)s'
    }
  },
  'ec2' => {
    'name' => 'EC2 Service',
    'project' => 'nova',
    'description' => 'OpenStack EC2 Service',
    'ports' => {
      'admin' => 8773,
      'internal' => 8773,
      'public' => 8773
    },
    'uris' => {
      'admin' => 'services/Admin',
      'internal' => 'services/Cloud',
      'public' => 'services/Cloud'
    }
  },
  # Cinder endpoint notes for Liberty: volume and volumev2 must both be v2
  'volume' => {
    'name' => 'Volume Service',
    'project' => 'cinder',
    'description' => 'OpenStack Volume Service',
    'ports' => {
      'admin' => 8776,
      'internal' => 8776,
      'public' => 8776
    },
    'uris' => {
      'admin' => 'v1/%(tenant_id)s',
      'internal' => 'v1/%(tenant_id)s',
      'public' => 'v1/%(tenant_id)s'
    }
  },
  'volumev2' => {
    'name' => 'cinderv2',
    'project' => 'cinder',
    'description' => 'OpenStack Volume Service V2',
    'ports' => {
      'admin' => 8776,
      'internal' => 8776,
      'public' => 8776
    },
    'uris' => {
      'admin' => 'v2/%(tenant_id)s',
      'internal' => 'v2/%(tenant_id)s',
      'public' => 'v2/%(tenant_id)s'
    }
  },
  # Glance
  'image' => {
    'name' => 'Image Service',
    'project' => 'glance',
    'description' => 'OpenStack Image Service',
    'ports' => {
      'admin' => 9292,
      'internal' => 9292,
      'public' => 9292
    },
    'uris' => {
      'admin' => 'v2',
      'internal' => 'v2',
      'public' => 'v2'
    }
  }
}

# canonical Liberty catalog

# default['bcpc']['catalog'] = {
#   'identity' => {
#     'name' => 'keystone',
#     'project' => 'keystone',
#     'description' => 'OpenStack Identity',
#     'ports' => {
#       'admin' => 35357,
#       'internal' => 5000,
#       'public' => 5000
#     },
#     'uris' => {
#       'admin' => 'v3',
#       'internal' => 'v3',
#       'public' => 'v3'
#     }
#   },
#   'compute' => {
#     'name' => 'Compute Service',
#     'project' => 'nova',
#     'description' => 'OpenStack Compute Service',
#     'ports' => {
#       'admin' => 8774,
#       'internal' => 8774,
#       'public' => 8774
#     },
#     'uris' => {
#       'admin' => 'v2/%(tenant_id)s',
#       'internal' => 'v2/%(tenant_id)s',
#       'public' => 'v2/%(tenant_id)s'
#     }
#   },
#   'ec2' => {
#     'name' => 'EC2 Service',
#     'project' => 'nova',
#     'description' => 'OpenStack EC2 Service',
#     'ports' => {
#       'admin' => 8773,
#       'internal' => 8773,
#       'public' => 8773
#     },
#     'uris' => {
#       'admin' => 'services/Admin',
#       'internal' => 'services/Cloud',
#       'public' => 'services/Cloud'
#     }
#   },
#   'volume' => {
#     'name' => 'Volume Service',
#     'project' => 'cinder',
#     'description' => 'OpenStack Volume Service',
#     'ports' => {
#       'admin' => 8776,
#       'internal' => 8776,
#       'public' => 8776
#     },
#     'uris' => {
#       'admin' => 'v2/%(tenant_id)s',
#       'internal' => 'v2/%(tenant_id)s',
#       'public' => 'v2/%(tenant_id)s'
#     }
#   },
#   'volumev2' => {
#     'name' => 'cinderv2',
#     'project' => 'cinder',
#     'description' => 'OpenStack Volume Service V2',
#     'ports' => {
#       'admin' => 8776,
#       'internal' => 8776,
#       'public' => 8776
#     },
#     'uris' => {
#       'admin' => 'v2/%(tenant_id)s',
#       'internal' => 'v2/%(tenant_id)s',
#       'public' => 'v2/%(tenant_id)s'
#     }
#   },
#   'image' => {
#     'name' => 'Image Service',
#     'project' => 'glance',
#     'description' => 'OpenStack Image Service',
#     'ports' => {
#       'admin' => 9292,
#       'internal' => 9292,
#       'public' => 9292
#     },
#     'uris' => {
#       'admin' => 'v2',
#       'internal' => 'v2',
#       'public' => 'v2'
#     }
#   }
# }
