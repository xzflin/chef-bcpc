name             'role-bcpc-node-head'
maintainer       'Bloomberg Finance L.P.'
maintainer_email 'YOUR_EMAIL'
license          'Apache 2.0'
description      'Installs/Configures role-bcpc-node-head'
long_description IO.read(File.join(File.dirname(__FILE__), 'README.md'))
version          '6.0.0'

depends          'role-bcpc-common', '>= 6.0.0'
depends          'bcpc-crond', '>= 6.0.0'
depends          'bcpc-sshd', '>= 6.0.0'
depends          'bcpc-health-check', '>= 6.0.0'
depends          'bcpc-networking', '>= 6.0.0'
