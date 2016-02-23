name             'bcpc-quota'
maintainer       'Bloomberg Finance L.P.'
maintainer_email 'bcpc@bloomberg.net'
license          'Apache 2.0'
description      'bcpc-quota manages OpenStack quotas'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '6.0.0'

conflicts        'bcpc'
depends          'bcpc-openstack-cinder',   '>= 6.0.0'
depends          'bcpc-openstack-common',   '>= 6.0.0'
depends          'bcpc-openstack-keystone', '>= 6.0.0'
depends          'bcpc-openstack-nova',     '>= 6.0.0'
