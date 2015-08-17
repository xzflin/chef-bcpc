name             'role-bcpc-node-work-osd'
maintainer       'Bloomberg Finance L.P.'
maintainer_email 'YOUR_EMAIL'
license          'Apache 2.0'
description      'Installs/Configures role-bcpc-node-work-osd'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '6.0.0'

depends          'role-bcpc-common',      '>= 6.0.0'
depends          'role-bcpc-node-common', '>= 6.0.0'
depends          'bcpc-ceph',             '>= 6.0.0'
depends          'bcpc-openstack-nova',   '>= 6.0.0'
