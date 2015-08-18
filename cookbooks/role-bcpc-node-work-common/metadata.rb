name             'role-bcpc-node-work-common'
maintainer       'Bloomberg Finance L.P.'
maintainer_email 'bcpc@bloomberg.net'
license          'Apache 2.0'
description      'Installs/Configures role-bcpc-node-work-common'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '6.0.0'

depends          'role-bcpc-common',      '>= 6.0.0'
depends          'role-bcpc-node-common', '>= 6.0.0'
depends          'bcpc-foundation',       '>= 6.0.0'
depends          'bcpc-openstack-nova',   '>= 6.0.0'
depends          'bcpc-health-check',     '>= 6.0.0'
