###########################################
#
#  Keystone Settings
#
###########################################
#
# Toggle Federated Authentication
default['bcpc']['keystone']['federation']['enabled'] = true
default['bcpc']['keystone']['federation']['kerberos']['users_group'] = 'krbusers'
default['bcpc']['keystone']['federation']['kerberos']['remote_id'] = 'KERB_ID'
default['bcpc']['keystone']['federation']['kerberos']['provider_name'] = 'kerb'
default['bcpc']['keystone']['federation']['kerberos']['mapping_name'] = 'kerberos_mapping'
default['bcpc']['keystone']['federation']['kerberos']['protocol_name'] = 'kerberos'
